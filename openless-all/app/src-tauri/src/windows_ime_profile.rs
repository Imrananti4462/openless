#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImeProfileKind {
    KeyboardLayout,
    TextService,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImeProfileSnapshot {
    kind: ImeProfileKind,
    lang_id: u16,
    clsid: Option<String>,
    profile_guid: Option<String>,
    hkl: Option<isize>,
}

impl ImeProfileSnapshot {
    pub fn text_service(lang_id: u16, clsid: String, profile_guid: String) -> Self {
        Self {
            kind: ImeProfileKind::TextService,
            lang_id,
            clsid: Some(clsid),
            profile_guid: Some(profile_guid),
            hkl: None,
        }
    }

    pub fn keyboard_layout(lang_id: u16, hkl: isize) -> Self {
        Self {
            kind: ImeProfileKind::KeyboardLayout,
            lang_id,
            clsid: None,
            profile_guid: None,
            hkl: Some(hkl),
        }
    }

    pub fn kind(&self) -> &ImeProfileKind {
        &self.kind
    }

    pub fn lang_id(&self) -> u16 {
        self.lang_id
    }

    pub fn clsid(&self) -> Option<&str> {
        self.clsid.as_deref()
    }

    pub fn profile_guid(&self) -> Option<&str> {
        self.profile_guid.as_deref()
    }

    pub fn hkl(&self) -> Option<isize> {
        self.hkl
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProfileRestoreDecision {
    RestoreSavedProfile,
    KeepCurrentProfile,
}

pub fn restore_decision(
    saved: Option<&ImeProfileSnapshot>,
    openless_profile_is_current: bool,
) -> ProfileRestoreDecision {
    if saved.is_some() && openless_profile_is_current {
        ProfileRestoreDecision::RestoreSavedProfile
    } else {
        ProfileRestoreDecision::KeepCurrentProfile
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WindowsImeProfileError {
    Unavailable(String),
    WindowsApi(String),
}

impl std::fmt::Display for WindowsImeProfileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unavailable(message) | Self::WindowsApi(message) => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for WindowsImeProfileError {}

pub type WindowsImeProfileResult<T> = Result<T, WindowsImeProfileError>;

#[cfg(not(target_os = "windows"))]
pub struct WindowsImeProfileManager;

#[cfg(not(target_os = "windows"))]
impl WindowsImeProfileManager {
    pub fn new() -> Self {
        Self
    }

    pub fn capture_active_profile(&self) -> WindowsImeProfileResult<ImeProfileSnapshot> {
        Err(WindowsImeProfileError::Unavailable(
            "Windows TSF profiles are only available on Windows".to_string(),
        ))
    }

    pub fn activate_openless_profile(&self) -> WindowsImeProfileResult<()> {
        Err(WindowsImeProfileError::Unavailable(
            "Windows TSF profiles are only available on Windows".to_string(),
        ))
    }

    pub fn restore_profile(&self, _snapshot: &ImeProfileSnapshot) -> WindowsImeProfileResult<()> {
        Err(WindowsImeProfileError::Unavailable(
            "Windows TSF profiles are only available on Windows".to_string(),
        ))
    }

    pub fn is_openless_profile_active(&self) -> WindowsImeProfileResult<bool> {
        Ok(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text_service_snapshot() -> ImeProfileSnapshot {
        ImeProfileSnapshot::text_service(
            0x0804,
            "{11111111-1111-1111-1111-111111111111}".to_string(),
            "{22222222-2222-2222-2222-222222222222}".to_string(),
        )
    }

    #[test]
    fn text_service_constructor_sets_required_profile_data() {
        let snapshot = text_service_snapshot();

        assert_eq!(snapshot.kind(), &ImeProfileKind::TextService);
        assert_eq!(snapshot.lang_id(), 0x0804);
        assert_eq!(
            snapshot.clsid(),
            Some("{11111111-1111-1111-1111-111111111111}")
        );
        assert_eq!(
            snapshot.profile_guid(),
            Some("{22222222-2222-2222-2222-222222222222}")
        );
        assert_eq!(snapshot.hkl(), None);
    }

    #[test]
    fn keyboard_layout_constructor_sets_required_hkl_data() {
        let snapshot = ImeProfileSnapshot::keyboard_layout(0x0409, 0x0409_0409);

        assert_eq!(snapshot.kind(), &ImeProfileKind::KeyboardLayout);
        assert_eq!(snapshot.lang_id(), 0x0409);
        assert_eq!(snapshot.clsid(), None);
        assert_eq!(snapshot.profile_guid(), None);
        assert_eq!(snapshot.hkl(), Some(0x0409_0409));
    }

    #[test]
    fn restore_is_required_when_openless_is_active_and_snapshot_exists() {
        assert_eq!(
            restore_decision(Some(&text_service_snapshot()), true),
            ProfileRestoreDecision::RestoreSavedProfile
        );
    }

    #[test]
    fn restore_is_skipped_when_snapshot_is_missing() {
        assert_eq!(
            restore_decision(None, true),
            ProfileRestoreDecision::KeepCurrentProfile
        );
    }

    #[test]
    fn restore_is_skipped_when_user_already_changed_away_from_openless() {
        assert_eq!(
            restore_decision(Some(&text_service_snapshot()), false),
            ProfileRestoreDecision::KeepCurrentProfile
        );
    }
}
