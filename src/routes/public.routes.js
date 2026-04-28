const router = require("express").Router();
const publicController = require("../controllers/public.controller");

// availability view
router.get("/:clinicId/availability", publicController.getAvailability);

// book slot
router.post("/book", publicController.bookSlot);

// cancel booking
router.post("/cancel", publicController.cancelBooking);

module.exports = router;