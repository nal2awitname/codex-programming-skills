"""Owned memory and scan state, implemented from the neutral lab contract."""

import ctypes


MIN_INT32 = -(2**31)
MAX_INT32 = 2**31 - 1
SLOT_BYTES = 4


class LabError(ValueError):
    """A stable, named validation/state error at the lab boundary."""

    def __init__(self, name: str):
        self.name = name
        super().__init__(name)


def int32(value: object) -> int:
    if type(value) is not int or not MIN_INT32 <= value <= MAX_INT32:
        raise LabError("invalid_value")
    return value


class OwnedIntBuffer:
    """Four-byte, little-endian slots in a ctypes allocation owned by this object.

    No method accepts a process ID, external address or memory handle. The only
    pointers used here are derived from this object's live allocation.
    """

    def __init__(self, initial: list[int]):
        if type(initial) is not list:
            raise LabError("invalid_scenario")
        values = [int32(value) for value in initial]
        self._count = len(values)
        # A nonzero allocation also permits an empty logical buffer.
        self._memory = ctypes.create_string_buffer(max(1, self._count * SLOT_BYTES))
        for index, value in enumerate(values):
            self.write(index, value)

    def __len__(self) -> int:
        return self._count

    def _index(self, index: object) -> int:
        if type(index) is not int or not 0 <= index < self._count:
            raise LabError("invalid_index")
        return index

    def read(self, index: int) -> int:
        index = self._index(index)
        address = ctypes.addressof(self._memory) + index * SLOT_BYTES
        data = ctypes.string_at(address, SLOT_BYTES)
        return int.from_bytes(data, byteorder="little", signed=True)

    def write(self, index: int, value: int) -> None:
        index = self._index(index)
        value = int32(value)
        data = value.to_bytes(SLOT_BYTES, byteorder="little", signed=True)
        address = ctypes.addressof(self._memory) + index * SLOT_BYTES
        ctypes.memmove(address, data, SLOT_BYTES)

    def values(self) -> list[int]:
        return [self.read(index) for index in range(self._count)]


class Scanner:
    """Retain candidate slots and their values at the last completed scan."""

    FIRST_MODES = ("exact", "unknown")
    NEXT_MODES = ("exact", "changed", "unchanged", "increased", "decreased")

    def __init__(self, buffer: OwnedIntBuffer):
        if not isinstance(buffer, OwnedIntBuffer):
            raise TypeError("Scanner requires an OwnedIntBuffer")
        self.buffer = buffer
        self._previous: dict[int, int] | None = None

    @property
    def started(self) -> bool:
        return self._previous is not None

    def reset(self) -> None:
        self._previous = None

    @staticmethod
    def _mode(mode: object, allowed: tuple[str, ...]) -> str:
        if type(mode) is not str or mode not in allowed:
            raise LabError("invalid_mode")
        return mode

    def _complete(self, selected: dict[int, int]) -> dict[str, list[int]]:
        self._previous = selected
        return {
            "offsets": [index * SLOT_BYTES for index in selected],
            "values": list(selected.values()),
        }

    def first(self, mode: str, value: object = None) -> dict[str, list[int]]:
        mode = self._mode(mode, self.FIRST_MODES)
        wanted = int32(value) if mode == "exact" else None
        current = self.buffer.values()
        selected = {
            index: current_value
            for index, current_value in enumerate(current)
            if mode == "unknown" or current_value == wanted
        }
        return self._complete(selected)

    def next(self, mode: str, value: object = None) -> dict[str, list[int]]:
        mode = self._mode(mode, self.NEXT_MODES)
        if self._previous is None:
            raise LabError("scan_not_started")
        wanted = int32(value) if mode == "exact" else None
        selected = {}
        for index, previous in self._previous.items():
            current = self.buffer.read(index)
            if mode == "exact":
                retain = current == wanted
            elif mode == "changed":
                retain = current != previous
            elif mode == "unchanged":
                retain = current == previous
            elif mode == "increased":
                retain = current > previous
            else:
                retain = current < previous
            if retain:
                selected[index] = current
        return self._complete(selected)

    def current_results(self) -> dict[str, list[int]]:
        """Read retained slots for display without completing another scan."""
        indices = () if self._previous is None else self._previous
        return {
            "offsets": [index * SLOT_BYTES for index in indices],
            "values": [self.buffer.read(index) for index in indices],
        }
