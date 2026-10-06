"""In-memory storage for notes."""
from notes import clock


class Store:
    def __init__(self):
        self.notes = {}

    def list_notes(self):
        return list(self.notes.values())

    def add_note(self, title, body):
        new_id = len(self.notes) + 1
        note = {"id": new_id, "title": title, "body": body, "created": clock.now()}
        self.notes[new_id] = note
        return note

    def reset(self):
        self.notes = {}
