import io
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from Host.cli import EmulatorShell, Connection, arguments


class SerialPort:
    def __init__(self):
        self.incoming = bytearray()
        self.sent = bytearray()
        self.closed = False
        self.condition = threading.Condition()
        self.fail_read = False

    def feed(self, data):
        with self.condition:
            self.incoming.extend(data)
            self.condition.notify_all()

    def read(self, count):
        with self.condition:
            if self.fail_read:
                raise OSError("Device disconnected")
            if not self.incoming:
                self.condition.wait(0.005)
            result = self.incoming[:count]
            del self.incoming[:len(result)]
            return bytes(result)

    def write(self, data):
        self.sent.extend(data)
        return len(data)

    def flush(self): pass
    def close(self): self.closed = True


class ShellTests(unittest.TestCase):
    def setUp(self):
        self.port = SerialPort()
        self.opens = []
        self.output = io.StringIO()
        def factory(name, **kwargs):
            self.opens.append((name, kwargs))
            return self.port
        self.shell = EmulatorShell(factory,
            lambda: [SimpleNamespace(device="COM4", description="Test board")], stdout=self.output)
        self.addCleanup(self.shell.close)

    def test_whole_interactive_session_uses_one_port(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "program with spaces.asm"
            path.write_text("LDI R0, 84\nSEND R0\n")
            self.shell.stdin = io.StringIO(
                f'ports\nconnect COM4\nload "{path}"\nstart\nhalt\nreset\npointer_reset\nstatus\nquit\n')
            self.shell.use_rawinput = False
            self.shell.cmdloop()
        self.assertEqual(len(self.opens), 1)
        self.assertEqual(self.opens[0][1]["baudrate"], 115200)
        self.assertEqual(self.port.sent, b"\x03\x04\x01\x00\x04\xa0\x0a\x00\x30\x02\x03\x04\x01")
        self.assertTrue(self.port.closed)
        self.assertIn("COM4: Test board", self.output.getvalue())

    def test_background_receive_and_partial_timeout(self):
        self.shell.onecmd("connect COM4")
        self.port.feed(b"\x00\x02T")
        time.sleep(0.15)  # Cross the background reader's packet timeout.
        self.port.feed(b"C\x00\x00")
        self.shell.onecmd("receive 2")
        self.assertIn("54 43  |TC|", self.output.getvalue())
        self.assertIn("  ||", self.output.getvalue())
        self.assertFalse(self.port.closed)
        self.shell.onecmd("halt")
        self.assertEqual(self.port.sent, b"\x03")

    def test_errors_return_to_prompt_without_sending(self):
        self.shell.onecmd("start")
        self.shell.onecmd("connect COM4")
        for line in ("connect COM5", "load", 'load "missing.asm"', "halt unexpected", "receive 0", "receive nope", "bogus"):
            self.assertFalse(self.shell.onecmd(line))
        self.assertEqual(self.port.sent, b"")
        self.shell.onecmd("start")
        self.shell.onecmd("")
        self.assertEqual(self.port.sent, b"\x02")
        self.assertEqual(len(self.opens), 1)

    def test_disconnect_and_eof_cleanup(self):
        self.shell.onecmd("connect COM4")
        connection = self.shell.connection
        self.shell.onecmd("disconnect")
        self.assertTrue(self.port.closed)
        self.assertFalse(connection.reader.is_alive())
        self.assertIsNone(self.shell.connection)
        self.assertTrue(self.shell.onecmd("EOF"))

    def test_receiver_error_is_reported_and_halt_still_available(self):
        self.shell.onecmd("connect COM4")
        self.port.feed(b"\xff")
        self.shell.onecmd("receive")
        self.assertIn("Unknown device command", self.output.getvalue())
        self.shell.onecmd("halt")
        self.assertEqual(self.port.sent, b"\x03")

    def test_idle_timeout_keeps_connection(self):
        connection = Connection(self.port)
        self.addCleanup(connection.close)
        with self.assertRaises(TimeoutError):
            connection.receive(0.01)
        self.port.feed(b"\x00\x01Z")
        self.assertEqual(connection.receive(1), b"Z")

    def test_queue_is_bounded_and_reports_drops(self):
        self.shell.onecmd("connect COM4")
        connection = self.shell.connection
        self.port.feed(b"\x00\x01T" * 4100)
        deadline = time.monotonic() + 3
        with connection.condition:
            while connection.dropped < 4 and not connection.error:
                remaining = deadline-time.monotonic()
                if remaining <= 0: break
                connection.condition.wait(remaining)
            self.assertEqual(len(connection.packets), 4096)
            self.assertEqual(connection.dropped, 4)
        self.shell.onecmd("status")
        self.assertIn("4 oldest packets dropped", self.output.getvalue())

    def test_windows_paths(self):
        self.assertEqual(arguments(r'"C:\My Programs\test.asm"'), [r'C:\My Programs\test.asm'])
        self.assertEqual(arguments(r'C:\Programs\test.asm'), [r'C:\Programs\test.asm'])


if __name__ == "__main__":
    unittest.main()
