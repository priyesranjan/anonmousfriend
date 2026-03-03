import express from 'express';
import { pool } from '../db.js';
import { authenticateAdmin } from '../middleware/auth.js';
import admin from '../config/firebase.js';

const router = express.Router();

// GET /api/marketing/newbies
// Get all users who have not recharged (offer_used = false AND balance < 10 AND no active subscriptions limits)
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
// Send bulk FCM push notifications to audience
router.post('/send-notification', authenticateAdmin, async (req, res) => {
    try {
        const { title, body } = req.body;

        if (!title || !body) {
            return res.status(400).json({ error: 'Title and body are required' });
        }

        // Step 1: Find all newbies who have an FCM token
        const query = `
      SELECT u.fcm_token
      FROM users u
      WHERE u.account_type = 'user'
        AND u.is_active = TRUE
        AND u.offer_used = FALSE
        AND u.fcm_token IS NOT NULL
    `;
        const result = await pool.query(query);
        let tokens = result.rows.map(row => row.fcm_token).filter(t => t);

        if (tokens.length === 0) {
            // Return success even if 0, because the query was successful, just no active users with app installed lately
            return res.json({ message: 'No users with FCM tokens found', successCount: 0 });
        }

        // FCM has a max limit of 500 tokens per multicast message
        let successCount = 0;

        // Chunk array by 500
        const chunkSize = 500;
        for (let i = 0; i < tokens.length; i += chunkSize) {
            const chunk = tokens.slice(i, i + chunkSize);
            const message = {
                notification: { title, body },
                data: { type: 'MARKETING_OFFER' },
                tokens: chunk,
            };

            try {
                const response = await admin.messaging().sendEachForMulticast(message);
                successCount += response.successCount;
            } catch (err) {
                console.error('Bulk FCM Error:', err);
            }
        }

        res.json({ message: 'Notifications broadcast complete', successCount });
    } catch (error) {
        console.error('Marketing Send Notification Error:', error);
        res.status(500).json({ error: 'Failed to broadcast notifications' });
    }
});

export default router;
