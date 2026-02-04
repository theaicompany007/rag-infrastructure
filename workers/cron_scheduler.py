"""
CRON Scheduler for RAG Service
Handles scheduled tasks like promoting drafts
"""
import logging
from typing import Dict, Any
from threading import Thread
import time
from datetime import datetime

logger = logging.getLogger(__name__)


class CronScheduler:
    """Simple CRON scheduler for periodic tasks"""
    
    def __init__(self):
        self.running = False
        self.thread = None
        self.interval = 300  # 5 minutes in seconds
        self.last_run = None
        self.run_count = 0
        
    def start(self):
        """Start the scheduler"""
        if self.running:
            logger.warning("Scheduler is already running")
            return
            
        self.running = True
        self.thread = Thread(target=self._run_loop, daemon=True)
        self.thread.start()
        logger.info(f"Scheduler started (interval: {self.interval}s)")
        
    def stop(self):
        """Stop the scheduler"""
        if not self.running:
            return
            
        self.running = False
        if self.thread:
            self.thread.join(timeout=5)
        logger.info("Scheduler stopped")
        
    def _run_loop(self):
        """Main scheduler loop"""
        while self.running:
            try:
                self.promote_scheduled_drafts()
                self.last_run = datetime.now()
                self.run_count += 1
            except Exception as e:
                logger.error(f"Scheduler task error: {e}", exc_info=True)
            
            # Sleep in small intervals to allow quick shutdown
            for _ in range(self.interval):
                if not self.running:
                    break
                time.sleep(1)
                
    def promote_scheduled_drafts(self):
        """Promote scheduled drafts (placeholder for actual implementation)"""
        # This is a placeholder - actual implementation would:
        # 1. Query database for drafts scheduled to be promoted
        # 2. Promote them based on schedule
        logger.debug("Running scheduled task: promote_scheduled_drafts")
        # TODO: Implement actual promotion logic
        
    def get_status(self) -> Dict[str, Any]:
        """Get scheduler status"""
        return {
            "running": self.running,
            "interval_seconds": self.interval,
            "last_run": self.last_run.isoformat() if self.last_run else None,
            "run_count": self.run_count
        }


# Singleton instance
_scheduler_instance = None


def get_cron_scheduler() -> CronScheduler:
    """Get the singleton scheduler instance"""
    global _scheduler_instance
    if _scheduler_instance is None:
        _scheduler_instance = CronScheduler()
    return _scheduler_instance
