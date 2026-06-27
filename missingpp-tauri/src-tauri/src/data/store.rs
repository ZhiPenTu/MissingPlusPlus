//! In-memory record store (replaces Swift `MissingStore`)

use anyhow::Result;
use chrono::Utc;
use std::sync::RwLock;
use uuid::Uuid;

use super::model::{Missing, RealityCheck, TriggerTag};
use super::persistence::Persistence;

pub struct Store {
    items: RwLock<Vec<Missing>>,
    persistence: Persistence,
}

impl Store {
    pub fn new(persistence: Persistence) -> Result<Self> {
        let items = persistence.load_records().unwrap_or_default();
        Ok(Self {
            items: RwLock::new(items),
            persistence,
        })
    }

    /// Snapshot sorted by `created_at` desc.
    pub fn snapshot(&self) -> Vec<Missing> {
        let mut items = self.items.read().unwrap().clone();
        items.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        items
    }

    pub fn get(&self, id: Uuid) -> Option<Missing> {
        self.items
            .read()
            .unwrap()
            .iter()
            .find(|i| i.id == id)
            .cloned()
    }

    pub fn add(&self, mut item: Missing) -> Result<Missing> {
        if item.id == Uuid::nil() {
            item.id = Uuid::new_v4();
        }
        if item.created_at.timestamp() == 0 {
            item.created_at = Utc::now();
        }
        let to_add = item.clone();
        {
            let mut items = self.items.write().unwrap();
            items.push(to_add.clone());
        }
        self.persist_and_emit()?;
        Ok(to_add)
    }

    pub fn mark_resolved(&self, id: Uuid) -> Result<()> {
        {
            let mut items = self.items.write().unwrap();
            if let Some(item) = items.iter_mut().find(|i| i.id == id) {
                item.resolved_at = Some(Utc::now());
            }
        }
        self.persist_and_emit()
    }

    pub fn attach_reality_check(&self, id: Uuid, check: RealityCheck) -> Result<()> {
        {
            let mut items = self.items.write().unwrap();
            if let Some(item) = items.iter_mut().find(|i| i.id == id) {
                item.reality_check = Some(check);
            }
        }
        self.persist_and_emit()
    }

    pub fn update_triggers(&self, id: Uuid, tags: Vec<TriggerTag>) -> Result<()> {
        {
            let mut items = self.items.write().unwrap();
            if let Some(item) = items.iter_mut().find(|i| i.id == id) {
                item.trigger_tags = tags;
            }
        }
        self.persist_and_emit()
    }

    pub fn delete(&self, id: Uuid) -> Result<()> {
        {
            let mut items = self.items.write().unwrap();
            items.retain(|i| i.id != id);
        }
        self.persist_and_emit()
    }

    pub fn clear_all(&self) -> Result<()> {
        {
            let mut items = self.items.write().unwrap();
            items.clear();
        }
        self.persist_and_emit()
    }

    /// Merge new items, dedup by id.
    pub fn merge(&self, incoming: Vec<Missing>) -> Result<usize> {
        let added = {
            let mut items = self.items.write().unwrap();
            let existing_ids: std::collections::HashSet<Uuid> =
                items.iter().map(|i| i.id).collect();
            let before = items.len();
            for item in incoming {
                if !existing_ids.contains(&item.id) {
                    items.push(item);
                }
            }
            items.len() - before
        };
        self.persist_and_emit()?;
        Ok(added)
    }

    pub fn replace_all(&self, new_items: Vec<Missing>) -> Result<()> {
        {
            let mut items = self.items.write().unwrap();
            *items = new_items;
        }
        self.persist_and_emit()
    }

    fn persist_and_emit(&self) -> Result<()> {
        self.persistence.save_records(&self.items.read().unwrap())?;
        // emit('store:changed') to all webviews — wired in main.rs
        Ok(())
    }
}
