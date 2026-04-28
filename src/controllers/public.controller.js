const slotService = require("../services/slot.service");

exports.getAvailability = async (req, res) => {
  const { clinicId } = req.params;
  const slots = await slotService.getPublicSlots(clinicId);
  res.json(slots);
};

exports.bookSlot = async (req, res) => {
  const result = await slotService.bookSlot(req.body);
  res.json(result);
};

exports.cancelBooking = async (req, res) => {
  const result = await slotService.cancelSlot(req.body);
  res.json(result);
};