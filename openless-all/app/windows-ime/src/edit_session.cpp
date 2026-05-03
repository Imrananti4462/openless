#include "edit_session.h"

#include <utility>

OpenLessEditSession::OpenLessEditSession(ITfContext* context,
                                         std::wstring text)
    : context_(context), text_(std::move(text)) {
  if (context_ != nullptr) {
    context_->AddRef();
  }
}

OpenLessEditSession::~OpenLessEditSession() {
  if (context_ != nullptr) {
    context_->Release();
    context_ = nullptr;
  }
}

STDMETHODIMP OpenLessEditSession::QueryInterface(REFIID iid, void** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  *object = nullptr;

  if (iid == IID_IUnknown || iid == IID_ITfEditSession) {
    *object = static_cast<ITfEditSession*>(this);
    AddRef();
    return S_OK;
  }

  return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) OpenLessEditSession::AddRef() {
  return static_cast<ULONG>(InterlockedIncrement(&ref_count_));
}

STDMETHODIMP_(ULONG) OpenLessEditSession::Release() {
  const ULONG count = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (count == 0) {
    delete this;
  }
  return count;
}

STDMETHODIMP OpenLessEditSession::DoEditSession(TfEditCookie edit_cookie) {
  if (context_ == nullptr) {
    return E_UNEXPECTED;
  }

  ITfInsertAtSelection* insert_at_selection = nullptr;
  HRESULT hr = context_->QueryInterface(IID_ITfInsertAtSelection,
                                        reinterpret_cast<void**>(
                                            &insert_at_selection));
  if (FAILED(hr)) {
    return hr;
  }

  ITfRange* query_range = nullptr;
  hr = insert_at_selection->InsertTextAtSelection(
      edit_cookie, TF_IAS_QUERYONLY, text_.c_str(),
      static_cast<LONG>(text_.size()), &query_range);
  if (query_range != nullptr) {
    query_range->Release();
    query_range = nullptr;
  }

  if (SUCCEEDED(hr)) {
    ITfRange* committed_range = nullptr;
    hr = insert_at_selection->InsertTextAtSelection(
        edit_cookie, 0, text_.c_str(), static_cast<LONG>(text_.size()),
        &committed_range);
    if (committed_range != nullptr) {
      committed_range->Release();
    }
  }

  insert_at_selection->Release();
  return hr;
}
