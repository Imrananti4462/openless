pub const OPENLESS_TSF_LANG_ID: u16 = 0x0804;
pub const OPENLESS_TEXT_SERVICE_CLSID_BRACED: &str = "{6B9F3F4F-5EE7-42D6-9C61-9F80B03A5D7D}";
pub const OPENLESS_PROFILE_GUID_BRACED: &str = "{9B5F5E04-23F6-47DA-9A26-D221F6C3F02E}";

#[cfg(target_os = "windows")]
fn parse_guid(value: &str) -> WindowsImeProfileResult<windows::core::GUID> {
    uuid::Uuid::parse_str(value)
        .map(|uuid| windows::core::GUID::from_u128(uuid.as_u128()))
        .map_err(|err| WindowsImeProfileError::WindowsApi(format!("invalid GUID {value}: {err}")))
}

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

#[cfg(target_os = "windows")]
pub struct WindowsImeProfileManager;

#[cfg(target_os = "windows")]
impl WindowsImeProfileManager {
    pub fn new() -> Self {
        Self
    }

    pub fn capture_active_profile(&self) -> WindowsImeProfileResult<ImeProfileSnapshot> {
        windows_impl::capture_active_profile()
    }

    pub fn activate_openless_profile(&self) -> WindowsImeProfileResult<()> {
        windows_impl::activate_openless_profile()
    }

    pub fn restore_profile(&self, snapshot: &ImeProfileSnapshot) -> WindowsImeProfileResult<()> {
        windows_impl::restore_profile(snapshot)
    }

    pub fn is_openless_profile_active(&self) -> WindowsImeProfileResult<bool> {
        windows_impl::is_openless_profile_active()
    }
}

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

#[cfg(target_os = "windows")]
mod windows_impl {
    use super::*;
    use std::ffi::c_void;
    use std::ptr;
    use windows::core::GUID;
    use windows::Win32::System::Com::{
        CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_INPROC_SERVER,
        COINIT_APARTMENTTHREADED,
    };
    use windows::Win32::UI::Input::KeyboardAndMouse::{GetKeyboardLayout, HKL};
    use windows::Win32::UI::TextServices::{
        CLSID_TF_InputProcessorProfiles, ITfInputProcessorProfileMgr, TF_INPUTPROCESSORPROFILE,
        TF_IPPMF_FORPROCESS, TF_PROFILETYPE_INPUTPROCESSOR, TF_PROFILETYPE_KEYBOARDLAYOUT,
    };

    struct ComApartment;

    impl ComApartment {
        fn initialize() -> WindowsImeProfileResult<Self> {
            unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) }
                .ok()
                .map_err(|err| {
                    WindowsImeProfileError::WindowsApi(format!("CoInitializeEx: {err}"))
                })?;
            Ok(Self)
        }
    }

    impl Drop for ComApartment {
        fn drop(&mut self) {
            unsafe {
                CoUninitialize();
            }
        }
    }

    pub fn capture_active_profile() -> WindowsImeProfileResult<ImeProfileSnapshot> {
        with_profile_manager(|manager| {
            let mut profile = TF_INPUTPROCESSORPROFILE::default();
            unsafe {
                manager.GetActiveProfile(&GUID::zeroed(), &mut profile)?;
            }

            if profile.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR {
                Ok(ImeProfileSnapshot::text_service(
                    profile.langid,
                    format!("{:?}", profile.clsid),
                    format!("{:?}", profile.guidProfile),
                ))
            } else {
                let hkl = unsafe { GetKeyboardLayout(0) };
                Ok(ImeProfileSnapshot::keyboard_layout(
                    lang_id_from_hkl(hkl),
                    hkl_to_isize(hkl),
                ))
            }
        })
    }

    pub fn activate_openless_profile() -> WindowsImeProfileResult<()> {
        let clsid = parse_guid(OPENLESS_TEXT_SERVICE_CLSID_BRACED)?;
        let profile_guid = parse_guid(OPENLESS_PROFILE_GUID_BRACED)?;

        with_profile_manager(|manager| unsafe {
            manager.ActivateProfile(
                TF_PROFILETYPE_INPUTPROCESSOR,
                OPENLESS_TSF_LANG_ID,
                &clsid,
                &profile_guid,
                null_hkl(),
                TF_IPPMF_FORPROCESS,
            )
        })
    }

    pub fn restore_profile(snapshot: &ImeProfileSnapshot) -> WindowsImeProfileResult<()> {
        match snapshot.kind() {
            ImeProfileKind::TextService => {
                let clsid = parse_required_guid("text service CLSID", snapshot.clsid())?;
                let profile_guid =
                    parse_required_guid("text service profile GUID", snapshot.profile_guid())?;

                with_profile_manager(|manager| unsafe {
                    manager.ActivateProfile(
                        TF_PROFILETYPE_INPUTPROCESSOR,
                        snapshot.lang_id(),
                        &clsid,
                        &profile_guid,
                        null_hkl(),
                        TF_IPPMF_FORPROCESS,
                    )
                })
            }
            ImeProfileKind::KeyboardLayout => {
                let hkl = HKL(snapshot.hkl().unwrap_or_default() as *mut c_void);
                let zero_guid = GUID::zeroed();

                with_profile_manager(|manager| unsafe {
                    manager.ActivateProfile(
                        TF_PROFILETYPE_KEYBOARDLAYOUT,
                        snapshot.lang_id(),
                        &zero_guid,
                        &zero_guid,
                        hkl,
                        TF_IPPMF_FORPROCESS,
                    )
                })
            }
        }
    }

    pub fn is_openless_profile_active() -> WindowsImeProfileResult<bool> {
        let snapshot = capture_active_profile()?;

        Ok(matches!(snapshot.kind(), ImeProfileKind::TextService)
            && snapshot.lang_id() == OPENLESS_TSF_LANG_ID
            && snapshot.clsid().map(normalize_guid_string).as_deref()
                == Some(OPENLESS_TEXT_SERVICE_CLSID_BRACED)
            && snapshot
                .profile_guid()
                .map(normalize_guid_string)
                .as_deref()
                == Some(OPENLESS_PROFILE_GUID_BRACED))
    }

    fn with_profile_manager<T>(
        operation: impl FnOnce(&ITfInputProcessorProfileMgr) -> windows::core::Result<T>,
    ) -> WindowsImeProfileResult<T> {
        let _com = ComApartment::initialize()?;
        let manager: ITfInputProcessorProfileMgr = unsafe {
            CoCreateInstance(&CLSID_TF_InputProcessorProfiles, None, CLSCTX_INPROC_SERVER)
        }
        .map_err(windows_api_error(
            "CoCreateInstance ITfInputProcessorProfileMgr",
        ))?;

        operation(&manager).map_err(windows_api_error("ITfInputProcessorProfileMgr operation"))
    }

    fn parse_required_guid(label: &str, value: Option<&str>) -> WindowsImeProfileResult<GUID> {
        parse_guid(value.ok_or_else(|| {
            WindowsImeProfileError::WindowsApi(format!("missing {label} in saved IME profile"))
        })?)
    }

    fn normalize_guid_string(value: &str) -> String {
        let upper = value.trim().to_ascii_uppercase();
        if upper.starts_with('{') && upper.ends_with('}') {
            upper
        } else {
            format!("{{{upper}}}")
        }
    }

    fn lang_id_from_hkl(hkl: HKL) -> u16 {
        (hkl_to_isize(hkl) as u32 & 0xffff) as u16
    }

    fn hkl_to_isize(hkl: HKL) -> isize {
        hkl.0 as isize
    }

    fn null_hkl() -> HKL {
        HKL(ptr::null_mut())
    }

    fn windows_api_error(
        context: &'static str,
    ) -> impl FnOnce(windows::core::Error) -> WindowsImeProfileError {
        move |err| WindowsImeProfileError::WindowsApi(format!("{context}: {err}"))
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

#[cfg(all(test, target_os = "windows"))]
mod windows_tests {
    use super::*;

    #[test]
    fn openless_profile_identifiers_are_fixed() {
        assert_eq!(OPENLESS_TSF_LANG_ID, 0x0804);
        assert_eq!(
            OPENLESS_TEXT_SERVICE_CLSID_BRACED,
            "{6B9F3F4F-5EE7-42D6-9C61-9F80B03A5D7D}"
        );
        assert_eq!(
            OPENLESS_PROFILE_GUID_BRACED,
            "{9B5F5E04-23F6-47DA-9A26-D221F6C3F02E}"
        );
    }
}
