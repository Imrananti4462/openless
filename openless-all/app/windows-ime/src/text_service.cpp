#include "text_service.h"

#include <new>

#include "edit_session.h"

extern LONG g_object_count;

OpenLessTextService::OpenLessTextService() {
  InterlockedIncrement(&g_object_count);
}

OpenLessTextService::~OpenLessTextService() {
  Deactivate();
  InterlockedDecrement(&g_object_count);
}

STDMETHODIMP OpenLessTextService::QueryInterface(REFIID iid, void** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  *object = nullptr;

  if (iid == IID_IUnknown || iid == IID_ITfTextInputProcessor ||
      iid == IID_ITfTextInputProcessorEx) {
    *object = static_cast<ITfTextInputProcessorEx*>(this);
    AddRef();
    return S_OK;
  }

  return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) OpenLessTextService::AddRef() {
  return static_cast<ULONG>(InterlockedIncrement(&ref_count_));
}

STDMETHODIMP_(ULONG) OpenLessTextService::Release() {
  const ULONG count = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (count == 0) {
    delete this;
  }
  return count;
}

STDMETHODIMP OpenLessTextService::Activate(ITfThreadMgr* thread_mgr,
                                           TfClientId client_id) {
  return ActivateEx(thread_mgr, client_id, 0);
}

STDMETHODIMP OpenLessTextService::ActivateEx(ITfThreadMgr* thread_mgr,
                                             TfClientId client_id,
                                             DWORD flags) {
  UNREFERENCED_PARAMETER(flags);

  if (thread_mgr == nullptr) {
    return E_INVALIDARG;
  }

  Deactivate();

  thread_mgr_ = thread_mgr;
  thread_mgr_->AddRef();
  client_id_ = client_id;

  const HRESULT hr = StartIpcServer();
  if (FAILED(hr)) {
    Deactivate();
    return hr;
  }

  return S_OK;
}

STDMETHODIMP OpenLessTextService::Deactivate() {
  StopIpcServer();

  if (thread_mgr_ != nullptr) {
    thread_mgr_->Release();
    thread_mgr_ = nullptr;
  }
  client_id_ = TF_CLIENTID_NULL;

  return S_OK;
}

HRESULT OpenLessTextService::SubmitTextFromPipe(
    const std::wstring& session_id,
    const std::wstring& text) {
  UNREFERENCED_PARAMETER(session_id);

  if (thread_mgr_ == nullptr || client_id_ == TF_CLIENTID_NULL) {
    return E_UNEXPECTED;
  }

  ITfDocumentMgr* document_mgr = nullptr;
  HRESULT hr = thread_mgr_->GetFocus(&document_mgr);
  if (FAILED(hr)) {
    return hr;
  }
  if (document_mgr == nullptr) {
    return E_FAIL;
  }

  ITfContext* context = nullptr;
  hr = document_mgr->GetTop(&context);
  document_mgr->Release();
  document_mgr = nullptr;
  if (FAILED(hr)) {
    return hr;
  }
  if (context == nullptr) {
    return E_FAIL;
  }

  auto* session = new (std::nothrow) OpenLessEditSession(context, text);
  if (session == nullptr) {
    context->Release();
    return E_OUTOFMEMORY;
  }

  HRESULT edit_result = S_OK;
  hr = context->RequestEditSession(client_id_, session,
                                   TF_ES_SYNC | TF_ES_READWRITE, &edit_result);
  session->Release();
  context->Release();

  if (FAILED(hr)) {
    return hr;
  }
  return edit_result;
}

HRESULT OpenLessTextService::StartIpcServer() {
  return S_OK;
}

void OpenLessTextService::StopIpcServer() {}
