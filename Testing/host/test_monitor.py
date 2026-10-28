import time
import tkinter as tk
import unittest
from types import SimpleNamespace
from Host.monitor import SerialMonitor, format_packet
from test_cli import SerialPort


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.root = tk.Tk()
        self.root.withdraw()
        self.port = SerialPort()
        self.app = SerialMonitor(self.root, lambda *a, **kw: self.port,
                                 lambda: [SimpleNamespace(device="TEST")])
        self.addCleanup(self.cleanup)

    def pump_until(self, predicate, timeout=3):
        deadline = time.monotonic() + timeout
        while not predicate() and time.monotonic() < deadline:
            self.root.update()
            time.sleep(0.005)
        self.assertTrue(predicate())

    def cleanup(self):
        if not self.app.destroyed:
            self.app.close()
            self.pump_until(lambda: self.app.destroyed)

    def connect(self):
        self.app.submit("connect TEST")
        self.pump_until(lambda: self.app.future is None)

    def text(self):
        return self.app.log.get("1.0", "end")

    def test_live_receive_preserves_command_input(self):
        self.connect()
        self.app.command.set("load my program")
        self.port.feed(b"\x00\x02TC")
        self.pump_until(lambda: "54 43  |TC|" in self.text())
        self.assertEqual(self.app.command.get(), "load my program")
        self.assertIn("receiving", self.app.status.get())
        self.assertEqual(self.port.sent, b"")

    def test_send_buttons_history_and_quit(self):
        self.connect()
        self.app.command.set("start")
        self.app.send_entry()
        self.assertEqual(self.app.command.get(), "")
        self.pump_until(lambda: self.app.future is None)
        self.assertEqual(self.port.sent, b"\x02")
        self.app.history_move(-1)
        self.assertEqual(self.app.command.get(), "start")
        self.app.history_move(1)
        self.assertEqual(self.app.command.get(), "")
        self.app.submit("halt")
        self.pump_until(lambda: self.app.future is None)
        self.app.submit("quit")
        self.pump_until(lambda: self.app.destroyed)
        self.assertEqual(self.port.sent, b"\x02\x03")
        self.assertTrue(self.port.closed)

    def test_slow_command_keeps_receive_and_typing_responsive(self):
        self.connect()
        original = self.app.shell.onecmd
        def slow(line):
            time.sleep(0.15)
            return original(line)
        self.app.shell.onecmd = slow
        self.app.submit("halt")
        self.app.command.set("start")
        self.assertFalse(self.app.submit("start"))
        self.port.feed(b"\x00\x01Z")
        self.pump_until(lambda: "|Z|" in self.text())
        self.assertEqual(self.app.command.get(), "start")
        self.pump_until(lambda: self.app.future is None)
        self.assertEqual(self.port.sent, b"\x03")

    def test_error_disconnect_and_log_limit(self):
        self.connect()
        self.port.feed(b"\xff")
        self.pump_until(lambda: "Receiver error" in self.text())
        self.assertIn("receiver stopped", self.app.status.get())
        self.app.submit("disconnect")
        self.pump_until(lambda: self.app.future is None)
        self.assertTrue(self.port.closed)
        self.app.append("x" * 150000)
        self.assertLessEqual(len(self.text()), self.app.MAX_LOG_CHARS+1)
        self.app.clear()
        self.assertEqual(self.text(), "\n")

    def test_display_formats(self):
        self.assertEqual(format_packet(b"T\x00", "Hex"), "RX  54 00\n")
        self.assertEqual(format_packet(b"T\x00", "ASCII"), "RX  T\\x00\n")
        self.assertEqual(format_packet(b"T", "Hex + ASCII"), "RX  54  |T|\n")


if __name__ == "__main__":
    unittest.main()
