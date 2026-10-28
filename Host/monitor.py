"""Desktop serial monitor with live packet display and a fixed command entry."""
from concurrent.futures import ThreadPoolExecutor
from queue import Empty, Queue
import tkinter as tk
from tkinter import filedialog, ttk
from tkinter.scrolledtext import ScrolledText
from .cli import EmulatorShell


class OutputQueue:
    def __init__(self):
        self.messages = Queue()
    def write(self, text):
        self.messages.put(text)
    def flush(self):
        pass


def format_packet(payload, mode):
    text = "".join(chr(value) if 32 <= value < 127 else f"\\x{value:02x}" for value in payload)
    if mode == "ASCII":
        return f"RX  {text}\n"
    if mode == "Hex":
        return f"RX  {payload.hex(' ')}\n"
    return f"RX  {payload.hex(' ')}  |{text}|\n"


class MonitorShell(EmulatorShell):
    def do_receive(self, line):
        """receive: data is displayed automatically in the monitor."""
        self.say("Incoming payload bytes are displayed automatically above.")


class SerialMonitor:
    POLL_MS = 20
    MAX_LOG_CHARS = 100_000

    def __init__(self, root, serial_factory, list_ports, port=None):
        self.root = root
        self.output = OutputQueue()
        self.shell = MonitorShell(serial_factory, list_ports, stdout=self.output)
        self.worker = ThreadPoolExecutor(max_workers=1)
        self.future = None
        self.closing = False
        self.destroyed = False
        self.last_connection = None
        self.last_error = None
        self.last_dropped = 0
        self.history = []
        self.history_index = 0
        root.title("Protocol Emulator — Serial Monitor")
        root.geometry("960x620")
        root.minsize(640, 380)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(1, weight=1)

        toolbar = ttk.Frame(root, padding=10)
        toolbar.grid(row=0, column=0, sticky="ew")
        ttk.Label(toolbar, text="Port").pack(side="left")
        self.port = tk.StringVar(value=port or "")
        self.port_box = ttk.Combobox(toolbar, textvariable=self.port, width=14)
        self.port_box.pack(side="left", padx=6)
        ttk.Button(toolbar, text="Refresh", command=self.refresh_ports).pack(side="left")
        ttk.Button(toolbar, text="Connect", command=lambda: self.submit(f'connect "{self.port.get()}"')).pack(side="left", padx=6)
        ttk.Button(toolbar, text="Disconnect", command=lambda: self.submit("disconnect")).pack(side="left")
        ttk.Label(toolbar, text="115200 · 8N1").pack(side="left", padx=12)
        self.mode = tk.StringVar(value="Hex + ASCII")
        ttk.Combobox(toolbar, textvariable=self.mode, values=("Hex + ASCII", "Hex", "ASCII"),
                     state="readonly", width=13).pack(side="right")
        self.log = ScrolledText(root, wrap="word", font=("Consolas", 10), state="disabled")
        self.log.grid(row=1, column=0, sticky="nsew", padx=10)

        controls = ttk.Frame(root, padding=10)
        controls.grid(row=2, column=0, sticky="ew")
        ttk.Button(controls, text="Load program…", command=self.choose_file).pack(side="left")
        for name in ("Start", "Halt", "Reset"):
            ttk.Button(controls, text=name, command=lambda n=name: self.submit(n.lower())).pack(side="left", padx=4)
        ttk.Button(controls, text="Clear log", command=self.clear).pack(side="right")
        self.autoscroll = tk.BooleanVar(value=True)
        ttk.Checkbutton(controls, text="Autoscroll", variable=self.autoscroll).pack(side="right", padx=8)

        bottom = ttk.Frame(root, padding=(10, 0, 10, 10))
        bottom.grid(row=3, column=0, sticky="ew")
        bottom.columnconfigure(1, weight=1)
        ttk.Label(bottom, text="Command").grid(row=0, column=0, padx=(0, 8))
        self.command = tk.StringVar()
        self.entry = ttk.Entry(bottom, textvariable=self.command)
        self.entry.grid(row=0, column=1, sticky="ew")
        self.entry.bind("<Return>", lambda event: self.send_entry())
        self.entry.bind("<Up>", lambda event: self.history_move(-1))
        self.entry.bind("<Down>", lambda event: self.history_move(1))
        self.send_button = ttk.Button(bottom, text="Send", command=self.send_entry)
        self.send_button.grid(row=0, column=2, padx=(8, 0))
        self.status = tk.StringVar(value="Disconnected")
        ttk.Label(root, textvariable=self.status, padding=(10, 0, 10, 8)).grid(row=4, column=0, sticky="ew")
        self.append("Connect to your board, then load a program and start it. Type help for commands.\n"
                    "RX shows packet payload bytes automatically. Commands have no device acknowledgements.\n")
        self.refresh_ports()
        self.entry.focus_set()
        root.protocol("WM_DELETE_WINDOW", self.close)
        self.poll_id = root.after(self.POLL_MS, self.poll)
        if port:
            self.submit(f'connect "{port}"')

    def refresh_ports(self):
        try:
            ports = [port.device for port in self.shell.list_ports()]
            self.port_box["values"] = ports
            if not self.port.get() and ports:
                self.port.set(ports[0])
        except OSError as error:
            self.append(f"Error: {error}\n")

    def append(self, text):
        self.log.configure(state="normal")
        self.log.insert("end", text)
        counts = self.log.count("1.0", "end-1c", "chars")
        length = counts[0] if counts else 0
        if length > self.MAX_LOG_CHARS:
            self.log.delete("1.0", f"1.0+{length-self.MAX_LOG_CHARS}c")
        self.log.configure(state="disabled")
        if self.autoscroll.get():
            self.log.see("end")

    def clear(self):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")

    def choose_file(self):
        path = filedialog.askopenfilename(title="Load program", filetypes=[
            ("Programs", "*.asm *.hex *.mem *.bin"), ("All files", "*.*")])
        if path:
            self.submit(f'load "{path}"')

    def send_entry(self):
        if self.submit(self.command.get()):
            self.command.set("")
        self.entry.focus_set()

    def submit(self, line):
        line = line.strip()
        if not line or self.closing:
            return False
        if self.future is not None:
            self.append("Please wait for the current command to finish.\n")
            return False
        self.history.append(line)
        self.history_index = len(self.history)
        self.append(f"> {line}\n")
        self.future = self.worker.submit(self.shell.onecmd, line)
        self.send_button.configure(state="disabled")
        return True

    def history_move(self, delta):
        self.history_index = max(0, min(len(self.history), self.history_index + delta))
        self.command.set(self.history[self.history_index] if self.history_index < len(self.history) else "")
        self.entry.icursor("end")
        return "break"

    def poll(self):
        if self.future is not None and self.future.done():
            try:
                if self.future.result():
                    self.closing = True
            except Exception as error:
                self.append(f"Error: {error}\n")
            self.future = None
            self.send_button.configure(state="normal")
        messages = []
        while True:
            try:
                messages.append(self.output.messages.get_nowait())
            except Empty:
                break
        connection = self.shell.connection
        if connection is not self.last_connection:
            self.last_connection = connection
            self.last_error = None
            self.last_dropped = 0
        if connection:
            with connection.condition:
                packets = list(connection.packets)
                connection.packets.clear()
                error, dropped = connection.error, connection.dropped
            messages.extend(format_packet(packet, self.mode.get()) for packet in packets)
            if error and error != self.last_error:
                messages.append(f"Receiver error: {error}\n")
                self.last_error = error
            if dropped != self.last_dropped:
                messages.append(f"Host queue overflow: {dropped} packets dropped in this connection.\n")
                self.last_dropped = dropped
            self.status.set(f"{self.shell.port} · 115200 baud · {dropped} dropped packets · "
                            + ("receiver stopped" if error else "receiving"))
        else:
            self.status.set("Disconnected")
        if messages:
            self.append("".join(messages))
        if self.closing and self.future is None:
            self.shell.close()
            self.worker.shutdown(wait=False)
            self.destroyed = True
            self.root.destroy()
            return
        self.poll_id = self.root.after(self.POLL_MS, self.poll)

    def close(self):
        # Let any pending serial write finish; never block Tk on a worker result.
        self.closing = True
        self.status.set("Closing connection…")


def run_monitor(serial_factory, list_ports, port=None):
    root = tk.Tk()
    SerialMonitor(root, serial_factory, list_ports, port)
    root.mainloop()
    return 0
