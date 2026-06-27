//! End-to-end test: create a Store, add a record with the React-shaped
//! JSON, verify it gets persisted and the file format matches what
//! useRecords would receive.

use missingpp_lib::data::{Missing, Mood, Intensity, Persistence, Store, TriggerTag};

fn unique_tmp_dir() -> std::path::PathBuf {
    let mut p = std::env::temp_dir();
    p.push(format!("missingpp-e2e-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&p);
    std::fs::create_dir_all(&p).unwrap();
    p
}

#[test]
fn e2e_add_record_via_store() {
    let tmp = unique_tmp_dir();
    let persistence = Persistence::new(tmp.clone()).unwrap();
    let store = Store::new(persistence).unwrap();

    // Simulate what the React submit does (lowercase enums, camelCase triggers):
    let item = Missing::new(
        "苏苏".to_string(),
        Mood::Delighted,
        Intensity::Strong,
        vec![TriggerTag::NoReply, TriggerTag::Alone],
    );
    let added = store.add(item).unwrap();
    assert_eq!(added.who, "苏苏");
    assert_eq!(added.mood, Mood::Delighted);
    assert_eq!(added.intensity, Intensity::Strong);

    // Read back from disk — must be JSON that React useRecords can parse.
    // save_records uses to_string_pretty so colons have a space.
    let path = tmp.join("records.json");
    let json = std::fs::read_to_string(&path).expect("records.json must be written");
    eprintln!("persisted JSON:\n{}", json);

    assert!(
        json.contains("\"mood\": \"delighted\""),
        "must serialize lowercase mood (with space after colon): {}",
        json
    );
    assert!(
        json.contains("\"intensity\": \"strong\""),
        "must serialize lowercase intensity: {}",
        json
    );
    assert!(json.contains("triggerTags"), "must use camelCase triggerTags: {}", json);
    assert!(json.contains("createdAt"), "must use camelCase createdAt: {}", json);

    // Reload through Persistence (same path the app uses on launch) and
    // verify we can read it back without loss.
    let p2 = Persistence::new(tmp.clone()).unwrap();
    let reloaded = p2.load_records().unwrap();
    assert_eq!(reloaded.len(), 1);
    assert_eq!(reloaded[0].who, "苏苏");
    assert_eq!(reloaded[0].mood, Mood::Delighted);
    assert_eq!(reloaded[0].intensity, Intensity::Strong);
    assert_eq!(reloaded[0].trigger_tags, vec![TriggerTag::NoReply, TriggerTag::Alone]);
}
