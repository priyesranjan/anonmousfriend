import express from 'express';
import { pool } from '../db.js';
import { authenticateAdmin } from '../middleware/auth.js';

const router = express.Router();

// GET /api/marketing/newbies
// Get all users who have not recharged (offer_used = false)
router.get('/newbies', authenticateAdmin, async (req, res) => {
    try {
        const query = `
      SELECT u.user_id, u.display_name, u.phone_number, u.email, u.created_at
      FROM users u
      LEFT JOIN wallets w ON u.user_id = w.user_id
      WHERE u.account_type = 'user'
        AND u.is_active = TRUE
        AND u.offer_used = FALSE
      ORDER BY u.created_at DESC
    `;
        const result = await pool.query(query);
        res.json(result.rows);
    } catch (error) {
        console.error('Fetch newbies error:', error);
        res.status(500).json({ error: 'Failed to fetch newbies' });
    }
});

// POST /api/marketing/send-notification
// TODO: FCM will be wired up in a future update
router.post('/send-notification', authenticateAdmin, async (req, res) => {
    try {
        const { title, body } = req.body;

        if (!title || !body) {
            return res.status(400).json({ error: 'Title and body are required' });
        }

        // Count eligible users 
        const query = `
      SELECT COUNT(*) as count
      FROM users u
      WHERE u.account_type = 'user'
        AND u.is_active = TRUE
        AND u.offer_used = FALSE
    `;
        const result = await pool.query(query);
        const count = parseInt(result.rows[0].count) || 0;

        res.json({
            message: 'FCM notifications not configured yet. Will be enabled soon.',
            eligible_users: count,
            successCount: 0
        });
    } catch (error) {
        console.error('Marketing Send Notification Error:', error);
        res.status(500).json({ error: 'Failed to process notification request' });
    }
});

export default router;
