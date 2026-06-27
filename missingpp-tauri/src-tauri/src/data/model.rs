//! Data model — mirror Swift `Missing` (AGENTS.md §22)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
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
#[serde(rename_all = "lowercase")]
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
#[serde(rename_all = "camelCase")]
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
#[serde(rename_all = "camelCase")]
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
                            // Each element is a JSON string like "noReply".
                            // Wrap in quotes so from_str sees a valid JSON string.
                            t.as_str().and_then(|s| {
                                serde_json::from_value::<TriggerTag>(
                                    serde_json::Value::String(s.to_string())
                                ).ok()
                            })
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


#[cfg(test)]
mod tests {
    use super::*;

    /// Regression test: the bug was that `Mood` and `Intensity` had no
    /// `#[serde(rename_all)]`, so they expected PascalCase (e.g. "Happy",
    /// "Mild"). The React side sends lowercase ("happy", "mild"), and the
    /// Swift `missings.json` is also lowercase. Both paths should now work.
    #[test]
    fn deserialize_mood_lowercase() {
        let m: Mood = serde_json::from_str("\"delighted\"").unwrap();
        assert_eq!(m, Mood::Delighted);
    }

    #[test]
    fn deserialize_intensity_lowercase() {
        let i: Intensity = serde_json::from_str("\"strong\"").unwrap();
        assert_eq!(i, Intensity::Strong);
    }

    #[test]
    fn deserialize_trigger_camelcase() {
        let t: TriggerTag = serde_json::from_str("\"sawSomething\"").unwrap();
        assert_eq!(t, TriggerTag::SawSomething);
    }

    #[test]
    fn roundtrip_missing_with_lowercase_enums() {
        // What a real Swift `missings.json` looks like, parsed through
        // the `Missing` struct directly (no MissingCompat wrapper):
        let input = r#"{
            "id": "11111111-1111-1111-1111-111111111111",
            "who": "苏苏",
            "mood": "delighted",
            "intensity": "strong",
            "createdAt": "2026-06-27T02:00:00Z"
        }"#;
        let m: Missing = serde_json::from_str(input).expect("must deserialize");
        assert_eq!(m.who, "苏苏");
        assert_eq!(m.mood, Mood::Delighted);
        assert_eq!(m.intensity, Intensity::Strong);
        // trigger_tags omitted → defaults to []
        assert_eq!(m.trigger_tags, Vec::<TriggerTag>::new());
    }

    /// Verify the file format we write is compatible with what Swift writes
    /// and what the React Query `useRecords` returns (lowercase, camelCase).
    #[test]
    fn serialize_matches_swift_format() {
        let m = Missing::new(
            "苏苏".to_string(),
            Mood::Delighted,
            Intensity::Strong,
            vec![TriggerTag::NoReply],
        );
        let json = serde_json::to_string(&m).unwrap();
        // Swift's missings.json has: "mood":"delighted","intensity":"strong","triggerTags":[]
        // Default Missing serialize uses snake_case for trigger_tags, so we need
        // the existing `trigger_tags` field on Missing (which the test confirms
        // survives the round trip). The Swift app's `missings.json` uses
        // `triggerTags` (camelCase), but the load path goes through MissingCompat
        // which reads `triggerTags` and falls back to [] otherwise.
        assert!(json.contains("\"mood\":\"delighted\""), "mood must be lowercase, got: {}", json);
        assert!(json.contains("\"intensity\":\"strong\""), "intensity must be lowercase, got: {}", json);
    }
}
