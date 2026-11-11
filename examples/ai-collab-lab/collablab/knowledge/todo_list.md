# To-do list manager
Kind: recipe
Keywords: todo, to-do, task list, checklist, รายการสิ่งที่ต้องทำ, งานที่ต้องทำ, ทูดู
Module: todo_list

A small in-memory to-do list with stable ids, completion and filtering.

```python module
"""An in-memory to-do list."""


class TodoList:
    """Keep to-do items with incrementing ids."""

    def __init__(self) -> None:
        self._items = {}
        self._next_id = 1

    def add(self, title: str) -> int:
        """Add an item and return its id."""
        title = title.strip()
        if not title:
            raise ValueError("title must not be empty")
        item_id = self._next_id
        self._items[item_id] = {"title": title, "done": False}
        self._next_id += 1
        return item_id

    def complete(self, item_id: int) -> None:
        """Mark an item as done."""
        if item_id not in self._items:
            raise KeyError(item_id)
        self._items[item_id]["done"] = True

    def pending(self) -> list:
        """Return titles of unfinished items in creation order."""
        return [item["title"] for item in self._items.values() if not item["done"]]

    def done(self) -> list:
        """Return titles of finished items in creation order."""
        return [item["title"] for item in self._items.values() if item["done"]]


if __name__ == "__main__":
    todo = TodoList()
    todo.complete(todo.add("write code"))
    todo.add("write docs")
    print(todo.pending(), todo.done())
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from todo_list import TodoList


class TodoListTests(unittest.TestCase):
    def test_lifecycle(self):
        todo = TodoList()
        first = todo.add("plan")
        todo.add("build")
        todo.complete(first)
        self.assertEqual(todo.pending(), ["build"])
        self.assertEqual(todo.done(), ["plan"])

    def test_invalid(self):
        todo = TodoList()
        with self.assertRaises(ValueError):
            todo.add("  ")
        with self.assertRaises(KeyError):
            todo.complete(99)


if __name__ == "__main__":
    unittest.main()
```
