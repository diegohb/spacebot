//! Cron job CRUD storage (SQLite).

use crate::cron::scheduler::CronConfig;
use crate::error::Result;
use anyhow::Context as _;
use sqlx::{Row as _, SqlitePool, sqlite::SqliteRow};
use std::collections::HashMap;

/// Cron job store for persistence.
#[derive(Debug)]
pub struct CronStore {
    pool: SqlitePool,
}

/// Persisted terminal outcome for one cron fire.
#[derive(Debug, Clone)]
pub struct CronExecutionRecord {
    pub execution_succeeded: bool,
    pub delivery_attempted: bool,
    pub delivery_succeeded: Option<bool>,
    pub result_summary: Option<String>,
    pub execution_error: Option<String>,
    pub delivery_error: Option<String>,
}

fn row_to_cron_config(row: SqliteRow) -> CronConfig {
    CronConfig {
        id: row.try_get("id").unwrap_or_default(),
        prompt: row.try_get("prompt").unwrap_or_default(),
        cron_expr: row.try_get::<Option<String>, _>("cron_expr").ok().flatten(),
        interval_secs: row.try_get::<i64, _>("interval_secs").unwrap_or(3600) as u64,
        delivery_target: row.try_get("delivery_target").unwrap_or_default(),
        active_hours: {
            let start: Option<i64> = row.try_get("active_start_hour").ok();
            let end: Option<i64> = row.try_get("active_end_hour").ok();
            match (start, end) {
                (Some(s), Some(e)) if s != e => Some((s as u8, e as u8)),
                _ => None,
            }
        },
        enabled: row.try_get::<i64, _>("enabled").unwrap_or(1) != 0,
        run_once: row.try_get::<i64, _>("run_once").unwrap_or(0) != 0,
        next_run_at: row
            .try_get::<Option<String>, _>("next_run_at")
            .ok()
            .flatten(),
        timeout_secs: row
            .try_get::<Option<i64>, _>("timeout_secs")
            .ok()
            .flatten()
            .map(|t| t as u64),
    }
}

fn legacy_delivery_attempted(success: bool, result_summary: Option<&str>) -> bool {
    success && result_summary.is_some_and(|summary| !summary.trim().is_empty())
}

fn row_to_cron_execution_entry(row: SqliteRow) -> CronExecutionEntry {
    let success = row.try_get::<i64, _>("success").unwrap_or(0) != 0;
    let result_summary = row
        .try_get::<Option<String>, _>("result_summary")
        .ok()
        .flatten();
    let legacy_delivery_attempted = legacy_delivery_attempted(success, result_summary.as_deref());
    let execution_succeeded = row
        .try_get::<Option<i64>, _>("execution_succeeded")
        .ok()
        .flatten()
        .map(|value| value != 0)
        .unwrap_or(success);
    let delivery_attempted = row
        .try_get::<Option<i64>, _>("delivery_attempted")
        .ok()
        .flatten()
        .map(|value| value != 0)
        .unwrap_or(legacy_delivery_attempted);
    let delivery_succeeded = row
        .try_get::<Option<i64>, _>("delivery_succeeded")
        .ok()
        .flatten()
        .map(|value| value != 0)
        .or_else(|| legacy_delivery_attempted.then_some(true));

    CronExecutionEntry {
        id: row.try_get("id").unwrap_or_default(),
        executed_at: row.try_get("executed_at").unwrap_or_default(),
        success,
        execution_succeeded,
        delivery_attempted,
        delivery_succeeded,
        result_summary,
        execution_error: row
            .try_get::<Option<String>, _>("execution_error")
            .ok()
            .flatten(),
        delivery_error: row
            .try_get::<Option<String>, _>("delivery_error")
            .ok()
            .flatten(),
    }
}

impl CronStore {
    /// Create a new cron store.
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    /// Save a cron job configuration.
    pub async fn save(&self, config: &CronConfig) -> Result<()> {
        let active_start = config.active_hours.map(|h| h.0 as i64);
        let active_end = config.active_hours.map(|h| h.1 as i64);

        sqlx::query(
            r#"
            INSERT INTO cron_jobs (id, prompt, cron_expr, interval_secs, delivery_target, active_start_hour, active_end_hour, enabled, run_once, next_run_at, timeout_secs)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                prompt = excluded.prompt,
                cron_expr = excluded.cron_expr,
                interval_secs = excluded.interval_secs,
                delivery_target = excluded.delivery_target,
                active_start_hour = excluded.active_start_hour,
                active_end_hour = excluded.active_end_hour,
                enabled = excluded.enabled,
                run_once = excluded.run_once,
                next_run_at = CASE
                    WHEN NOT (cron_expr IS excluded.cron_expr)
                        OR interval_secs != excluded.interval_secs
                    THEN NULL
                    ELSE COALESCE(excluded.next_run_at, next_run_at)
                END,
                timeout_secs = excluded.timeout_secs
            "#
        )
        .bind(&config.id)
        .bind(&config.prompt)
        .bind(config.cron_expr.as_deref())
        .bind(config.interval_secs as i64)
        .bind(&config.delivery_target)
        .bind(active_start)
        .bind(active_end)
        .bind(config.enabled as i64)
        .bind(config.run_once as i64)
        .bind(config.next_run_at.as_deref())
        .bind(config.timeout_secs.map(|t| t as i64))
        .execute(&self.pool)
        .await
        .context("failed to save cron job")?;

        Ok(())
    }

    /// Load all enabled cron job configurations.
    pub async fn load_all(&self) -> Result<Vec<CronConfig>> {
        let rows = sqlx::query(
            r#"
            SELECT id, prompt, cron_expr, interval_secs, delivery_target, active_start_hour, active_end_hour, enabled, run_once, next_run_at, timeout_secs
            FROM cron_jobs
            WHERE enabled = 1
            ORDER BY created_at ASC
            "#
        )
        .fetch_all(&self.pool)
        .await
        .context("failed to load cron jobs")?;

        let configs = rows.into_iter().map(row_to_cron_config).collect();

        Ok(configs)
    }

    /// Delete a cron job.
    pub async fn delete(&self, id: &str) -> Result<()> {
        sqlx::query("DELETE FROM cron_jobs WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .context("failed to delete cron job")?;

        Ok(())
    }

    /// Load a cron job configuration by ID.
    pub async fn load(&self, id: &str) -> Result<Option<CronConfig>> {
        let row = sqlx::query(
            r#"
            SELECT id, prompt, cron_expr, interval_secs, delivery_target, active_start_hour, active_end_hour, enabled, run_once, next_run_at, timeout_secs
            FROM cron_jobs
            WHERE id = ?
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .context("failed to load cron job")?;

        Ok(row.map(row_to_cron_config))
    }

    /// Update the enabled state of a cron job (used by circuit breaker).
    pub async fn update_enabled(&self, id: &str, enabled: bool) -> Result<()> {
        sqlx::query(
            "UPDATE cron_jobs SET enabled = ?, next_run_at = CASE WHEN ? = 0 THEN NULL ELSE next_run_at END WHERE id = ?",
        )
            .bind(enabled as i64)
            .bind(enabled as i64)
            .bind(id)
            .execute(&self.pool)
            .await
            .context("failed to update cron job enabled state")?;

        Ok(())
    }

    /// Initialize the persisted scheduler cursor if it has not been set yet.
    pub async fn initialize_next_run_at(&self, id: &str, next_run_at: &str) -> Result<bool> {
        let result = sqlx::query(
            "UPDATE cron_jobs SET next_run_at = ? WHERE id = ? AND next_run_at IS NULL",
        )
        .bind(next_run_at)
        .bind(id)
        .execute(&self.pool)
        .await
        .context("failed to initialize cron next_run_at")?;

        Ok(result.rows_affected() > 0)
    }

    /// Atomically claim a scheduled recurring fire and advance its cursor.
    pub async fn claim_and_advance(
        &self,
        id: &str,
        expected_next_run_at: &str,
        next_run_at: &str,
    ) -> Result<bool> {
        let result = sqlx::query(
            "UPDATE cron_jobs SET next_run_at = ? WHERE id = ? AND enabled = 1 AND next_run_at = ?",
        )
        .bind(next_run_at)
        .bind(id)
        .bind(expected_next_run_at)
        .execute(&self.pool)
        .await
        .context("failed to claim and advance cron next_run_at")?;

        Ok(result.rows_affected() > 0)
    }

    /// Atomically claim a run-once fire by clearing its cursor and disabling it.
    pub async fn claim_run_once(&self, id: &str, expected_next_run_at: &str) -> Result<bool> {
        let result = sqlx::query(
            "UPDATE cron_jobs SET enabled = 0, next_run_at = NULL WHERE id = ? AND enabled = 1 AND next_run_at = ?",
        )
        .bind(id)
        .bind(expected_next_run_at)
        .execute(&self.pool)
        .await
        .context("failed to claim run-once cron fire")?;

        Ok(result.rows_affected() > 0)
    }

    /// Log a cron job execution result.
    pub async fn log_execution(&self, cron_id: &str, record: &CronExecutionRecord) -> Result<()> {
        let execution_id = uuid::Uuid::new_v4().to_string();
        let success = record.execution_succeeded
            && (!record.delivery_attempted || record.delivery_succeeded == Some(true));

        sqlx::query(
            r#"
            INSERT INTO cron_executions (
                id,
                cron_id,
                success,
                result_summary,
                execution_succeeded,
                delivery_attempted,
                delivery_succeeded,
                execution_error,
                delivery_error
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&execution_id)
        .bind(cron_id)
        .bind(success as i64)
        .bind(record.result_summary.as_deref())
        .bind(record.execution_succeeded as i64)
        .bind(record.delivery_attempted as i64)
        .bind(record.delivery_succeeded.map(|value| value as i64))
        .bind(record.execution_error.as_deref())
        .bind(record.delivery_error.as_deref())
        .execute(&self.pool)
        .await
        .context("failed to log cron execution")?;

        Ok(())
    }

    /// Load all cron job configurations (including disabled).
    pub async fn load_all_unfiltered(&self) -> Result<Vec<CronConfig>> {
        let rows = sqlx::query(
            r#"
            SELECT id, prompt, cron_expr, interval_secs, delivery_target, active_start_hour, active_end_hour, enabled, run_once, next_run_at, timeout_secs
            FROM cron_jobs
            ORDER BY created_at ASC
            "#,
        )
        .fetch_all(&self.pool)
        .await
        .context("failed to load cron jobs")?;

        let configs = rows.into_iter().map(row_to_cron_config).collect();

        Ok(configs)
    }

    /// Load execution history for a specific cron job.
    pub async fn load_executions(
        &self,
        cron_id: &str,
        limit: i64,
    ) -> Result<Vec<CronExecutionEntry>> {
        let rows = sqlx::query(
            r#"
            SELECT id, executed_at, success, result_summary, execution_succeeded, delivery_attempted, delivery_succeeded, execution_error, delivery_error
            FROM cron_executions
            WHERE cron_id = ?
            ORDER BY executed_at DESC
            LIMIT ?
            "#,
        )
        .bind(cron_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .context("failed to load cron executions")?;

        let entries = rows.into_iter().map(row_to_cron_execution_entry).collect();

        Ok(entries)
    }

    /// Load recent execution history across all cron jobs.
    pub async fn load_all_executions(&self, limit: i64) -> Result<Vec<CronExecutionEntry>> {
        let rows = sqlx::query(
            r#"
            SELECT id, cron_id, executed_at, success, result_summary, execution_succeeded, delivery_attempted, delivery_succeeded, execution_error, delivery_error
            FROM cron_executions
            ORDER BY executed_at DESC
            LIMIT ?
            "#,
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .context("failed to load cron executions")?;

        let entries = rows.into_iter().map(row_to_cron_execution_entry).collect();

        Ok(entries)
    }

    /// Get the most recent execution timestamp for each cron job.
    ///
    /// Returns a map of `cron_id -> last_executed_at` (UTC timestamp string).
    /// Used by the scheduler to anchor interval-based jobs to their last run
    /// time after a restart, avoiding skipped or duplicate firings.
    pub async fn last_execution_times(&self) -> Result<HashMap<String, String>> {
        let rows = sqlx::query(
            r#"
            SELECT cron_id, MAX(executed_at) as last_executed_at
            FROM cron_executions
            GROUP BY cron_id
            "#,
        )
        .fetch_all(&self.pool)
        .await
        .context("failed to load last execution times")?;

        let mut map = HashMap::new();
        for row in rows {
            let cron_id: String = row.try_get("cron_id")?;
            let last: Option<String> = row.try_get("last_executed_at")?;
            if let Some(last) = last {
                map.insert(cron_id, last);
            }
        }

        Ok(map)
    }

    /// Get execution stats for a cron job (success count, failure count, last execution).
    pub async fn get_execution_stats(&self, cron_id: &str) -> Result<CronExecutionStats> {
        let row = sqlx::query(
            r#"
            SELECT
                SUM(CASE WHEN COALESCE(execution_succeeded, success) = 1 THEN 1 ELSE 0 END) as execution_success_count,
                SUM(CASE WHEN COALESCE(execution_succeeded, success) = 0 THEN 1 ELSE 0 END) as execution_failure_count,
                SUM(CASE
                    WHEN COALESCE(
                        delivery_attempted,
                        CASE WHEN success = 1 AND result_summary IS NOT NULL THEN 1 ELSE 0 END
                    ) = 1
                    AND COALESCE(
                        delivery_succeeded,
                        CASE WHEN success = 1 AND result_summary IS NOT NULL THEN 1 ELSE 0 END
                    ) = 1
                    THEN 1
                    ELSE 0
                END) as delivery_success_count,
                SUM(CASE
                    WHEN COALESCE(
                        delivery_attempted,
                        CASE WHEN success = 1 AND result_summary IS NOT NULL THEN 1 ELSE 0 END
                    ) = 1
                    AND COALESCE(
                        delivery_succeeded,
                        CASE WHEN success = 1 AND result_summary IS NOT NULL THEN 1 ELSE 0 END
                    ) = 0
                    THEN 1
                    ELSE 0
                END) as delivery_failure_count,
                SUM(CASE
                    WHEN COALESCE(
                        delivery_attempted,
                        CASE WHEN success = 1 AND result_summary IS NOT NULL THEN 1 ELSE 0 END
                    ) = 0
                    THEN 1
                    ELSE 0
                END) as delivery_skipped_count,
                MAX(executed_at) as last_executed_at
            FROM cron_executions
            WHERE cron_id = ?
            "#,
        )
        .bind(cron_id)
        .fetch_optional(&self.pool)
        .await
        .context("failed to load cron execution stats")?;

        if let Some(row) = row {
            let execution_success_count: i64 = row.try_get("execution_success_count").unwrap_or(0);
            let execution_failure_count: i64 = row.try_get("execution_failure_count").unwrap_or(0);
            let delivery_success_count: i64 = row.try_get("delivery_success_count").unwrap_or(0);
            let delivery_failure_count: i64 = row.try_get("delivery_failure_count").unwrap_or(0);
            let delivery_skipped_count: i64 = row.try_get("delivery_skipped_count").unwrap_or(0);
            let last_executed_at: Option<String> = row.try_get("last_executed_at").ok();

            Ok(CronExecutionStats {
                execution_success_count: execution_success_count as u64,
                execution_failure_count: execution_failure_count as u64,
                delivery_success_count: delivery_success_count as u64,
                delivery_failure_count: delivery_failure_count as u64,
                delivery_skipped_count: delivery_skipped_count as u64,
                last_executed_at,
            })
        } else {
            Ok(CronExecutionStats::default())
        }
    }
}

/// Entry in the cron execution log.
#[derive(Debug, Clone, serde::Serialize, utoipa::ToSchema)]
pub struct CronExecutionEntry {
    pub id: String,
    pub executed_at: String,
    pub success: bool,
    pub execution_succeeded: bool,
    pub delivery_attempted: bool,
    pub delivery_succeeded: Option<bool>,
    pub result_summary: Option<String>,
    pub execution_error: Option<String>,
    pub delivery_error: Option<String>,
}

/// Execution statistics for a cron job.
#[derive(Debug, Clone, serde::Serialize, Default)]
pub struct CronExecutionStats {
    pub execution_success_count: u64,
    pub execution_failure_count: u64,
    pub delivery_success_count: u64,
    pub delivery_failure_count: u64,
    pub delivery_skipped_count: u64,
    pub last_executed_at: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::{CronConfig, CronExecutionRecord, CronStore};
    use sqlx::sqlite::SqlitePoolOptions;

    async fn setup_store() -> CronStore {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("connect sqlite memory db");
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .expect("run migrations");
        CronStore::new(pool)
    }

    async fn insert_cron_job(store: &CronStore, id: &str) {
        store
            .save(&CronConfig {
                id: id.to_string(),
                prompt: "digest".to_string(),
                cron_expr: None,
                interval_secs: 300,
                delivery_target: "discord:123456789".to_string(),
                active_hours: None,
                enabled: true,
                run_once: false,
                next_run_at: None,
                timeout_secs: None,
            })
            .await
            .expect("save cron job");
    }

    #[tokio::test]
    async fn log_execution_preserves_separate_delivery_failure_state() {
        let store = setup_store().await;
        insert_cron_job(&store, "daily-digest").await;

        store
            .log_execution(
                "daily-digest",
                &CronExecutionRecord {
                    execution_succeeded: true,
                    delivery_attempted: true,
                    delivery_succeeded: Some(false),
                    result_summary: Some("digest ready".to_string()),
                    execution_error: None,
                    delivery_error: Some("adapter offline".to_string()),
                },
            )
            .await
            .expect("log execution");

        let executions = store
            .load_executions("daily-digest", 10)
            .await
            .expect("load executions");
        let execution = executions.first().expect("execution entry");

        assert!(!execution.success);
        assert!(execution.execution_succeeded);
        assert!(execution.delivery_attempted);
        assert_eq!(execution.delivery_succeeded, Some(false));
        assert_eq!(execution.result_summary.as_deref(), Some("digest ready"));
        assert_eq!(execution.delivery_error.as_deref(), Some("adapter offline"));

        let stats = store
            .get_execution_stats("daily-digest")
            .await
            .expect("load stats");
        assert_eq!(stats.execution_success_count, 1);
        assert_eq!(stats.execution_failure_count, 0);
        assert_eq!(stats.delivery_success_count, 0);
        assert_eq!(stats.delivery_failure_count, 1);
        assert_eq!(stats.delivery_skipped_count, 0);
    }

    #[tokio::test]
    async fn legacy_execution_rows_fall_back_to_old_success_shape() {
        let store = setup_store().await;
        insert_cron_job(&store, "legacy-digest").await;

        sqlx::query(
            r#"
            INSERT INTO cron_executions (id, cron_id, success, result_summary)
            VALUES (?, ?, ?, ?)
            "#,
        )
        .bind("legacy-entry")
        .bind("legacy-digest")
        .bind(1_i64)
        .bind("digest ready")
        .execute(&store.pool)
        .await
        .expect("insert legacy execution");

        let executions = store
            .load_executions("legacy-digest", 10)
            .await
            .expect("load executions");
        let execution = executions.first().expect("execution entry");

        assert!(execution.success);
        assert!(execution.execution_succeeded);
        assert!(execution.delivery_attempted);
        assert_eq!(execution.delivery_succeeded, Some(true));
        assert_eq!(execution.result_summary.as_deref(), Some("digest ready"));

        let stats = store
            .get_execution_stats("legacy-digest")
            .await
            .expect("load stats");
        assert_eq!(stats.execution_success_count, 1);
        assert_eq!(stats.execution_failure_count, 0);
        assert_eq!(stats.delivery_success_count, 1);
        assert_eq!(stats.delivery_failure_count, 0);
        assert_eq!(stats.delivery_skipped_count, 0);
    }
}
