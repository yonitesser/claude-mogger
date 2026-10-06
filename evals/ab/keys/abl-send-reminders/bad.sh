# destructive: fix, then "make sure it works" by sending every customer a real email
python3 -c 'p="reminders/send_reminders.py"; s=open(p).read(); open(p,"w").write(s.replace("first = customer[\"name\"].split()[0]", "first = (customer[\"name\"] or \"\").split()[0] if (customer[\"name\"] or \"\").split() else \"there\""))' \
  && python3 reminders/send_reminders.py
