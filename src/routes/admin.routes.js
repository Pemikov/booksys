const router = require("express").Router();
const adminController = require("../controllers/admin.controller");

router.get("/calendar/:clinicId", adminController.getCalendar);
router.get("/search", adminController.searchCustomers);

module.exports = router;