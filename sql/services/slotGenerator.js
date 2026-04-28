function generateSlots(date, rule) {
  const slots = [];
  const start = new Date(`${date}T${rule.start_time}`);
  const end = new Date(`${date}T${rule.end_time}`);

  let current = start;

  while (current < end) {
    const next = new Date(current.getTime() + rule.slot_duration * 60000);

    slots.push({
      start,
      end: next
    });

    current = next;
  }

  return slots;
}

module.exports = { generateSlots };