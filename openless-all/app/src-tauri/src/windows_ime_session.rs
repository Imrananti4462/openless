use crate::types::InsertStatus;
use crate::windows_ime_ipc::{ImeSubmitRequest, WindowsImeIpcServer};
use crate::windows_ime_profile::{
    restore_decision, ImeProfileSnapshot, ProfileRestoreDecision, WindowsImeProfileManager,
};
use crate::windows_ime_protocol::ImeSubmitStatus;

#[derive(Debug)]
pub enum WindowsImeSessionError {
    Profile(String),
    Ipc(String),
}

impl std::fmt::Display for WindowsImeSessionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Profile(message) | Self::Ipc(message) => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for WindowsImeSessionError {}

pub fn map_ime_status_to_insert_status(status: ImeSubmitStatus) -> InsertStatus {
    match status {
        ImeSubmitStatus::Committed => InsertStatus::Inserted,
        ImeSubmitStatus::Rejected | ImeSubmitStatus::Failed => InsertStatus::CopiedFallback,
    }
}

pub fn should_fallback_after_ime_result(status: ImeSubmitStatus) -> bool {
    !matches!(status, ImeSubmitStatus::Committed)
}

#[derive(Debug)]
pub struct PreparedWindowsImeSession {
    saved_profile: Option<ImeProfileSnapshot>,
    openless_activated: bool,
}

impl PreparedWindowsImeSession {
    pub fn unavailable() -> Self {
        Self {
            saved_profile: None,
            openless_activated: false,
        }
    }

    pub fn is_ready_for_tsf_submit(&self) -> bool {
        self.saved_profile.is_some() && self.openless_activated
    }
}

pub struct WindowsImeSessionController {
    profile_manager: WindowsImeProfileManager,
    ipc_server: WindowsImeIpcServer,
}

impl WindowsImeSessionController {
    pub fn new() -> Self {
        Self {
            profile_manager: WindowsImeProfileManager::new(),
            ipc_server: WindowsImeIpcServer::new(),
        }
    }

    pub fn prepare_session(&self) -> PreparedWindowsImeSession {
        #[cfg(target_os = "windows")]
        {
            let saved_profile = match self.profile_manager.capture_active_profile() {
                Ok(snapshot) => snapshot,
                Err(error) => {
                    let error = WindowsImeSessionError::Profile(error.to_string());
                    log::warn!("[windows-ime] capture active profile failed: {error}");
                    return PreparedWindowsImeSession::unavailable();
                }
            };

            match self.profile_manager.activate_openless_profile() {
                Ok(()) => PreparedWindowsImeSession {
                    saved_profile: Some(saved_profile),
                    openless_activated: true,
                },
                Err(error) => {
                    let error = WindowsImeSessionError::Profile(error.to_string());
                    log::warn!("[windows-ime] activate OpenLess profile failed: {error}");
                    PreparedWindowsImeSession::unavailable()
                }
            }
        }

        #[cfg(not(target_os = "windows"))]
        {
            PreparedWindowsImeSession::unavailable()
        }
    }

    pub async fn submit_prepared(
        &self,
        prepared: &PreparedWindowsImeSession,
        request: ImeSubmitRequest,
    ) -> Result<InsertStatus, WindowsImeSessionError> {
        if !prepared.is_ready_for_tsf_submit() {
            return Ok(InsertStatus::CopiedFallback);
        }

        let status = self
            .ipc_server
            .submit_text(request)
            .await
            .map_err(|error| WindowsImeSessionError::Ipc(error.to_string()))?;
        if should_fallback_after_ime_result(status) {
            log::warn!("[windows-ime] TSF submit returned {status:?}; falling back to clipboard");
        }
        Ok(map_ime_status_to_insert_status(status))
    }

    pub fn restore_session(&self, prepared: PreparedWindowsImeSession) {
        let should_restore = match self.profile_manager.is_openless_profile_active() {
            Ok(openless_active) => {
                restore_decision(prepared.saved_profile.as_ref(), openless_active)
            }
            Err(error) => {
                log::warn!("[windows-ime] check active profile before restore failed: {error}");
                ProfileRestoreDecision::KeepCurrentProfile
            }
        };

        if should_restore != ProfileRestoreDecision::RestoreSavedProfile {
            return;
        }

        let Some(saved_profile) = prepared.saved_profile.as_ref() else {
            return;
        };

        if let Err(error) = self.profile_manager.restore_profile(saved_profile) {
            log::warn!("[windows-ime] restore saved profile failed: {error}");
        }
    }
}

impl Default for WindowsImeSessionController {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn committed_ime_result_maps_to_inserted() {
        assert_eq!(
            map_ime_status_to_insert_status(ImeSubmitStatus::Committed),
            InsertStatus::Inserted
        );
    }

    #[test]
    fn rejected_ime_result_requests_fallback() {
        assert!(should_fallback_after_ime_result(ImeSubmitStatus::Rejected));
        assert!(should_fallback_after_ime_result(ImeSubmitStatus::Failed));
        assert!(!should_fallback_after_ime_result(
            ImeSubmitStatus::Committed
        ));
    }
}
