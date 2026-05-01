#pragma once

#include <msctf.h>
#include <string>
#include <windows.h>

class OpenLessEditSession final : public ITfEditSession {
 public:
  OpenLessEditSession(ITfContext* context, std::wstring text);
  OpenLessEditSession(const OpenLessEditSession&) = delete;
  OpenLessEditSession& operator=(const OpenLessEditSession&) = delete;
  ~OpenLessEditSession();

  STDMETHODIMP QueryInterface(REFIID iid, void** object) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;
  STDMETHODIMP DoEditSession(TfEditCookie edit_cookie) override;

 private:
  LONG ref_count_ = 1;
  ITfContext* context_ = nullptr;
  std::wstring text_;
};
