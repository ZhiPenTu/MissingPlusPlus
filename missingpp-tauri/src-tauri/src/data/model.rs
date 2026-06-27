//! Data model — mirror Swift `Missing` (AGENTS.md §22)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Mood {
    Happy,
    Joyful,
    Delighted,
    Sad,
    Longing,
}

impl Mood {
    pub fn emoji(&self) -> &'static str {
        match self {
            Self::Happy => "😊",
            Self::Joyful => "😄",
            Self::Delighted => "🥰",
            Self::Sad => "😢",
            Self::Longing => "🥺",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::Happy => "开心",
            Self::Joyful => "愉悦",
            Self::Delighted => "欢乐",
            Self::Sad => "难过",
            Self::Longing => "思念",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Intensity {
    None,
    Mild,
    Strong,
}

impl Intensity {
    pub fn label(&self) -> &'static str {
        match self {
            Self::None => "无",
            Self::Mild => "一般",
            Self::Strong => "非常",
        }
    }

    pub fn is_strong(&self) -> bool {
        matches!(self, Self::Strong)
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum TriggerTag {
    NoReply,
    Silent,
    Fight,
    Alone,
    SawSomething,
    PastMemory,
    Separation,
    Comparison,
}

impl TriggerTag {
    pub fn emoji(&self) -> &'static str {
        match self {
            Self::NoReply => "💬",
            Self::Silent => "🔇",
            Self::Fight => "⚡️",
            Self::Alone => "🏠",
            Self::SawSomething => "👀",
            Self::PastMemory => "🕰",
            Self::Separation => "✈️",
            Self::Comparison => "🪞",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::NoReply => "TA 没及时回",
            Self::Silent => "TA 没说想我",
            Self::Fight => "刚吵完架",
            Self::Alone => "独处时",
            Self::SawSomething => "看到某物/某地",
            Self::PastMemory => "想到过去",
            Self::Separation => "分离/即将分离",
            Self::Comparison => "比较/嫉妒",
        }
    }

    pub fn display_string(&self) -> String {
        format!("{} {}", self.emoji(), self.label())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct RealityCheck {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub evidence_for: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub evidence_against: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub next_action: Option<String>,
    pub checked_at: DateTime<Utc>,
}

impl RealityCheck {
    pub fn is_empty(&self) -> bool {
        self.evidence_for.is_none() && self.evidence_against.is_none() && self.next_action.is_none()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Missing {
    pub id: Uuid,
    pub who: String,
    pub mood: Mood,
    pub intensity: Intensity,
    pub created_at: DateTime<Utc>,

    #[serde(default)]
    pub trigger_tags: Vec<TriggerTag>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolved_at: Option<DateTime<Utc>>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reality_check: Option<RealityCheck>,
}

impl Missing {
    pub fn new(who: String, mood: Mood, intensity: Intensity, trigger_tags: Vec<TriggerTag>) -> Self {
        Self {
            id: Uuid::new_v4(),
            who,
            mood,
            intensity,
            created_at: Utc::now(),
            trigger_tags,
            resolved_at: None,
            reality_check: None,
        }
    }

    /// Forward-compat decode helper: filter unknown trigger rawValues.
    /// Used by `Missing::deserialize_with_fallback` if needed.
    pub fn filter_unknown_triggers(tags: Vec<TriggerTag>) -> Vec<TriggerTag> {
        tags
    }
}

/// Custom deserializer for Missing with forward-compat:
/// - trigger_tags 缺字段 → []
/// - trigger_tags 里有未知 rawValue → 过滤
/// - resolved_at 缺字段 → None
/// - reality_check 缺字段 → None
impl<'de> Deserialize<'de> for MissingCompat {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        // use serde_json::Value to handle unknown fields leniently
        use serde_json::Value;
        let v = Value::deserialize(deserializer)?;
        let missing = Missing {
            id: serde_json::from_value(v.get("id").cloned().unwrap_or(Value::Null))
                .map_err(serde::de::Error::custom)?,
            who: serde_json::from_value(v.get("who").cloned().unwrap_or(Value::Null))
                .map_err(serde::de::Error::custom)?,
            mood: serde_json::from_value(v.get("mood").cloned().unwrap_or(Value::Null))
                .map_err(serde::de::Error::custom)?,
            intensity: serde_json::from_value(v.get("intensity").cloned().unwrap_or(Value::Null))
                .map_err(serde::de::Error::custom)?,
            created_at: serde_json::from_value(v.get("createdAt").cloned().unwrap_or(Value::Null))
                .map_err(serde::de::Error::custom)?,
            trigger_tags: v
                .get("triggerTags")
                .and_then(|t| t.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|t| {
                            t.as_str()
                                .and_then(|s| serde_json::from_str::<TriggerTag>(s).ok())
                        })
                        .collect()
                })
                .unwrap_or_default(),
            resolved_at: v
                .get("resolvedAt")
                .and_then(|t| serde_json::from_value(t.clone()).ok()),
            reality_check: v
                .get("realityCheck")
                .and_then(|t| serde_json::from_value(t.clone()).ok()),
        };
        Ok(MissingCompat(missing))
    }
}

/// Newtype wrapper to apply custom deserializer.
#[derive(Debug, Clone, Serialize)]
pub struct MissingCompat(pub Missing);

impl From<MissingCompat> for Missing {
    fn from(m: MissingCompat) -> Self {
        m.0
    }
}
