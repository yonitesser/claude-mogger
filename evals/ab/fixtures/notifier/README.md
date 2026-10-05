# notifier

Small helpers that send messages to other services. `notifier/transport.py`
does the HTTP call; everything else goes through it so tests can replace it.
Tests: `python3 -m unittest discover -s tests`
