"""An original, minimal desktop for the application-owned sample buffer."""

import tkinter as tk
from tkinter import ttk

from .core import LabError, OwnedIntBuffer, Scanner
from .scenario import DEMO_INITIAL


class LabWindow:
    def __init__(self, root: tk.Tk):
        self.root = root
        root.title("ValueScanLab — Owned Buffer")
        root.minsize(640, 440)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(0, weight=1)
        self.buffer = OwnedIntBuffer(list(DEMO_INITIAL))
        self.scanner = Scanner(self.buffer)
        self.value_var = tk.StringVar(root, value="137")
        self.mode_var = tk.StringVar(root, value="exact")
        self.sample_var = tk.StringVar(root)
        self.status_var = tk.StringVar(root, value="Ready. Start with exact 137.")

        body = ttk.Frame(root, padding=18)
        body.grid(sticky="nsew")
        body.columnconfigure(0, weight=1)
        body.rowconfigure(4, weight=1)
        ttk.Label(body, text="ValueScanLab", font=("Segoe UI", 19, "bold")).grid(sticky="w")
        ttk.Label(body, text="Owned buffer · signed 32-bit little-endian slots").grid(row=1, sticky="w", pady=(2, 14))

        controls = ttk.Frame(body)
        controls.grid(row=2, sticky="ew", pady=(0, 12))
        ttk.Label(controls, text="Search value").grid(row=0, column=0, sticky="w")
        ttk.Entry(controls, textvariable=self.value_var, width=16).grid(row=1, column=0, sticky="w", padx=(0, 12))
        ttk.Label(controls, text="Scan mode").grid(row=0, column=1, sticky="w")
        ttk.Combobox(
            controls,
            textvariable=self.mode_var,
            values=("exact", "unknown", "changed", "unchanged", "increased", "decreased"),
            state="readonly",
            width=15,
        ).grid(row=1, column=1, padx=(0, 12))
        self.first_button = ttk.Button(controls, text="Initial search", command=lambda: self._scan(True))
        self.first_button.grid(row=1, column=2, padx=(0, 8))
        self.refine_button = ttk.Button(controls, text="Refine", command=lambda: self._scan(False))
        self.refine_button.grid(row=1, column=3)

        sample = ttk.Frame(body)
        sample.grid(row=3, sticky="ew", pady=(0, 12))
        ttk.Label(sample, textvariable=self.sample_var).grid(row=0, column=0, sticky="w", padx=(0, 12))
        self.lower_button = ttk.Button(sample, text="Lower sample (−17)", command=self._lower)
        self.lower_button.grid(row=0, column=1, padx=(0, 8))
        self.restart_button = ttk.Button(sample, text="Restart", command=self._restart)
        self.restart_button.grid(row=0, column=2)

        self.results = ttk.Treeview(body, columns=("offset", "value"), show="headings", height=9)
        self.results.heading("offset", text="Byte offset")
        self.results.heading("value", text="Current value")
        self.results.column("offset", anchor="center", width=160)
        self.results.column("value", anchor="center", width=260)
        self.results.grid(row=4, sticky="nsew")
        ttk.Label(body, textvariable=self.status_var, wraplength=600).grid(row=5, sticky="w", pady=(10, 4))
        ttk.Label(body, text="Only this application's six-slot buffer is read or modified.").grid(row=6, sticky="w")
        self._refresh()

    def _refresh(self) -> None:
        self.sample_var.set(f"Sample slot 2 (offset 8): {self.buffer.read(2)}")
        children = self.results.get_children()
        if children:
            self.results.delete(*children)
        current = self.scanner.current_results()
        for offset, value in zip(current["offsets"], current["values"]):
            self.results.insert("", "end", values=(offset, value))

    def _scan(self, first: bool) -> None:
        try:
            mode = self.mode_var.get()
            value = None
            if mode == "exact":
                try:
                    value = int(self.value_var.get(), 10)
                except ValueError:
                    raise LabError("invalid_value") from None
            result = (self.scanner.first if first else self.scanner.next)(mode, value)
            self.status_var.set(f"{len(result['offsets'])} match(es).")
        except LabError as error:
            self.status_var.set(f"Error: {error.name}")
        self._refresh()

    def _lower(self) -> None:
        try:
            self.buffer.write(2, self.buffer.read(2) - 17)
            self.status_var.set("Sample lowered. Refine to compare with the last scan.")
        except LabError as error:
            self.status_var.set(f"Error: {error.name}")
        self._refresh()

    def _restart(self) -> None:
        self.buffer = OwnedIntBuffer(list(DEMO_INITIAL))
        self.scanner = Scanner(self.buffer)
        self.value_var.set("137")
        self.mode_var.set("exact")
        self.status_var.set("Restarted. Initial values restored; results cleared.")
        self._refresh()


def launch() -> None:
    try:
        root = tk.Tk()
    except tk.TclError as error:
        raise RuntimeError("Tk display is unavailable") from error
    try:
        LabWindow(root)
        root.mainloop()
    finally:
        try:
            root.destroy()
        except tk.TclError:
            pass
