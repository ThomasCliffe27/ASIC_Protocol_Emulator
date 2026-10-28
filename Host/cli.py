"""Live UART serial monitor: python Host/cli.py [--port COM4] [--terminal]."""
import argparse
import cmd
from collections import deque
import shlex
import threading
import time
if __package__:
    from .protocol import CPUClient, program_bytes, POINTER_RESET, START, HALT, RESET
else:
    # Direct script execution must also make the sibling Assembler package visible.
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from Host.protocol import CPUClient, program_bytes, POINTER_RESET, START, HALT, RESET


class Connection:
    """One serial session; read continuously while the user types commands."""
    def __init__(self, transport):
        self.transport = transport
        self.client = CPUClient(transport)
        self.packets = deque(maxlen=4096)
        self.dropped = 0
        self.error = None
        self.condition = threading.Condition()
        self.stop = threading.Event()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        while not self.stop.is_set():
            try:
                payload = self.client.receive(0.1)
            except TimeoutError:
                continue
            except (OSError, ValueError) as error:
                with self.condition:
                    self.error = str(error)
                    self.condition.notify_all()
                return
            with self.condition:
                if len(self.packets) == self.packets.maxlen:
                    self.dropped += 1
                self.packets.append(payload)
                self.condition.notify_all()

    def receive(self, timeout=5.0):
        deadline = time.monotonic() + timeout
        with self.condition:
            while not self.packets:
                if self.error:
                    raise OSError(self.error)
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("No packet available; the connection remains open")
                self.condition.wait(remaining)
            return self.packets.popleft()

    def close(self):
        self.stop.set()
        # Serial read has a 50 ms timeout, so the reader terminates promptly.
        self.reader.join()
        self.transport.close()


def arguments(line):
    # Preserve Windows backslashes and accept quoted filenames containing spaces.
    return [part[1:-1] if len(part) >= 2 and part[0] == part[-1] and part[0] in "\"'"
            else part for part in shlex.split(line, posix=False)]


class EmulatorShell(cmd.Cmd):
    prompt = "emulator> "
    intro = "Protocol emulator interactive shell. Type help for commands."

    def __init__(self, serial_factory, list_ports, **kwargs):
        super().__init__(**kwargs)
        self.serial_factory = serial_factory
        self.list_ports = list_ports
        self.connection = None
        self.port = None

    def say(self, message):
        self.stdout.write(str(message) + "\n")
        self.stdout.flush()

    def emptyline(self) -> bool:
        # Never repeat a previous hardware command or exit on an empty line.
        return False

    def onecmd(self, line):
        try:
            return super().onecmd(line)
        except (OSError, ValueError, TimeoutError) as error:
            self.say(f"Error: {error}")
            return False

    def connected(self):
        if self.connection is None:
            raise ValueError("Not connected. Use: connect COM4")
        return self.connection

    @staticmethod
    def no_arguments(line):
        if line.strip():
            raise ValueError("This command takes no arguments")

    def do_ports(self, line):
        """ports: list available serial ports."""
        self.no_arguments(line)
        for port in self.list_ports():
            self.say(f"{port.device}: {port.description}")

    def do_connect(self, line):
        """connect PORT: open a persistent 115200 8N1 connection."""
        parts = arguments(line)
        if len(parts) != 1:
            raise ValueError("Usage: connect PORT")
        if self.connection:
            raise ValueError("Already connected; use disconnect first")
        transport = self.serial_factory(parts[0], baudrate=115200, bytesize=8,
            parity="N", stopbits=1, timeout=0.05, write_timeout=5,
            xonxoff=False, rtscts=False, dsrdtr=False)
        self.connection = Connection(transport)
        self.port = parts[0]
        self.say(f"Connected to {self.port}. Commands have no device acknowledgements.")

    def do_disconnect(self, line):
        """disconnect: close the serial connection; CPU execution is unchanged."""
        self.no_arguments(line)
        self.close()
        self.say("Disconnected.")

    def close(self):
        if self.connection:
            self.connection.close()
            self.connection = None
            self.port = None

    def do_load(self, line):
        """load FILE: validate program, halt/reset CPU, reset pointer, upload; leave halted."""
        parts = arguments(line)
        if len(parts) != 1:
            raise ValueError('Usage: load "path to program.asm"')
        connection = self.connected()
        data = program_bytes(parts[0])
        connection.client.load(data)
        self.say(f"Sent {len(data)} program bytes. CPU left halted; use start.")

    def control(self, line, command, name):
        self.no_arguments(line)
        self.connected().client.control(command)
        self.say(f"Sent {name}.")

    def do_start(self, line):
        """start: start or resume execution."""
        self.control(line, START, "start")

    def do_halt(self, line):
        """halt: pause execution, preserving CPU state."""
        self.control(line, HALT, "halt")

    def do_reset(self, line):
        """reset: reset CPU state and leave halted; preserve program memory."""
        self.control(line, RESET, "reset")

    def do_pointer_reset(self, line):
        """pointer_reset: reset the program loading pointer to zero."""
        self.control(line, POINTER_RESET, "pointer reset")

    def do_receive(self, line):
        """receive [COUNT]: display packets as hex and ASCII (default 1); wait up to 5s each."""
        parts = arguments(line)
        if len(parts) > 1:
            raise ValueError("Usage: receive [COUNT]")
        count = int(parts[0]) if parts else 1
        if not 1 <= count <= 4096:
            raise ValueError("COUNT must be between 1 and 4096")
        connection = self.connected()
        for _ in range(count):
            payload = connection.receive()
            ascii_text = "".join(chr(value) if 32 <= value < 127 else "." for value in payload)
            self.say(f"{payload.hex(' ')}  |{ascii_text}|")

    def do_status(self, line):
        """status: show connection, buffered packets and host-side drops (not CPU status)."""
        self.no_arguments(line)
        if not self.connection:
            self.say("Disconnected.")
            return
        connection = self.connection
        with connection.condition:
            self.say(f"{self.port}: {len(connection.packets)} buffered packets; "
                     f"{connection.dropped} oldest packets dropped; "
                     f"receiver: {connection.error or 'active'}")

    def do_quit(self, line):
        """quit: close the port and exit; use halt first to stop the CPU."""
        self.no_arguments(line)
        self.close()
        return True

    def do_EOF(self, line):
        self.say("")
        return self.do_quit(line)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Connect on startup; otherwise use connect at the prompt")
    parser.add_argument("--terminal", action="store_true", help="Use the text-only interactive shell")
    args = parser.parse_args(argv)
    try:
        import serial
        from serial.tools.list_ports import comports
    except ImportError:
        parser.exit(1, "Install serial support: python -m pip install -r Host/requirements.txt\n")
    if not args.terminal:
        from Host.monitor import run_monitor
        return run_monitor(serial.Serial, comports, args.port)
    shell = EmulatorShell(serial.Serial, comports)
    try:
        if args.port:
            shell.onecmd(f'connect "{args.port}"')
        while True:
            try:
                shell.cmdloop()
                break
            except KeyboardInterrupt:
                shell.say("\nInterrupted. Connection remains open; type quit to exit.")
                shell.intro = None
    finally:
        shell.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
