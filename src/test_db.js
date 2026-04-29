const db = require('./config/db');

(async () => {
  try {
    const result = await db.query(`
      SELECT 
        current_database() AS database_name,
        current_user AS user_name,
        NOW() AS time
    `);

    const row = result.rows[0];

    console.log('--- Database Info ---');
    console.log(`Database: ${row.database_name}`);
    console.log(`User: ${row.user_name}`);
    console.log(`Time: ${row.time}`);
  } catch (err) {
    console.error('Query failed:', err.message);
  }
})();