const express = require("express");

const publicRoutes = require("./routes/public.routes");
const adminRoutes = require("./routes/admin.routes");
const customerRoutes = require("./routes/customer.routes");

const app = express();

app.use(express.json());

// routes
app.use("/public", publicRoutes);
app.use("/admin", adminRoutes);
app.use("/customer", customerRoutes);

module.exports = app;