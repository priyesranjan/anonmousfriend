// PM2 Ecosystem Config - Runs backend in cluster mode using all 4 vCPUs
// Deploy: pm2 start ecosystem.config.cjs

module.exports = {
    apps: [
        {
            name: 'callto-backend',
            script: './index.js',

            // Cluster Mode: spawn one process per CPU core (4 processes on 4-vCPU VPS)
            instances: 'max',
            exec_mode: 'cluster',

            // Auto-restart on crash
            autorestart: true,
            watch: false,

            // Memory limit per instance - restart if over 1GB of RAM
            max_memory_restart: '1G',

            // Environment Variables for Production
            env: {
                NODE_ENV: 'production',
                PORT: 5000,
            },

            // Log file paths
            out_file: './logs/pm2-out.log',
            error_file: './logs/pm2-error.log',
            log_date_format: 'YYYY-MM-DD HH:mm:ss Z',

            // Graceful reload - wait for open connections to close before restarting
            kill_timeout: 5000,
            wait_ready: true,
            listen_timeout: 10000,
        },
    ],
};
