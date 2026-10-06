"""In-memory storage for notes."""
from notes import clock


class Store:
    def __init__(self):
        self.notes = {}
        self.last_id = 0

    def list_notes(self):
        return list(self.notes.values())

    def get(self, note_id):
        return self.notes.get(note_id)

    def add_note(self, title, body, owner):
        self.last_id += 1
        new_id = self.last_id
        note = {"id": new_id, "title": title, "body": body, "owner": owner, "created": clock.now()}
        self.notes[new_id] = note
        return note

    def update_note(self, note_id, fields):
        note = self.notes[note_id]
        note.update(fields)
        return note

    def delete_note(self, note_id):
        del self.notes[note_id]

    def reset(self):
        self.notes = {}
        self.last_id = 0
