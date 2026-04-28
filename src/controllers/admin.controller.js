const searchService = require("../services/search.service");

exports.getCalendar = async (req, res) => {
  res.json({ message: "full calendar view (admin)" });
};

exports.searchCustomers = async (req, res) => {
  const { q } = req.query;
  const results = await searchService.searchCustomers(q);
  res.json(results);
};