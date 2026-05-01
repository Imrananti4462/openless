#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImeProfileKind {
    KeyboardLayout,
    TextService,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImeProfileSnapshot {
    pub kind: ImeProfileKind,
    pub lang_id: u16,
    pub clsid: Option<String>,
    pub profile_guid: Option<String>,
    pub hkl: Option<isize>,
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
        ImeProfileSnapshot {
            kind: ImeProfileKind::TextService,
            lang_id: 0x0804,
            clsid: Some("{11111111-1111-1111-1111-111111111111}".to_string()),
            profile_guid: Some("{22222222-2222-2222-2222-222222222222}".to_string()),
            hkl: None,
        }
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
