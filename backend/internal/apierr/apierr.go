// Package apierr は API 仕様の「エラー」にあるエラーコードを定義する。
//
// アプリ（app/lib/core/api/uramichi_api.dart）は code と HTTP ステータスで動きを変えるので、
// 値を変えるときはアプリの担当者と相談する。
package apierr

import (
	"errors"
	"fmt"
	"net/http"
)

type Code string

const (
	BadRequest       Code = "bad_request"
	NotCheckedIn     Code = "not_checked_in"
	Unauthenticated  Code = "unauthenticated"
	PermissionDenied Code = "permission_denied"
	// LoginRequired は、Google アカウントでログインせずに（匿名で）呼び出したこと。
	LoginRequired  Code = "login_required"
	NotFound       Code = "not_found"
	OriginNotFound Code = "origin_not_found"
	Internal       Code = "internal"
	NotImplemented Code = "not_implemented"
	// PlaceNotFound は、チェックインしようとした place ID の場所が存在しないこと。
	PlaceNotFound Code = "place_not_found"
	// TooFar は、チェックインしようとした場所から現在地が離れていること。
	TooFar Code = "too_far"
	// PlacesUnavailable は、チェックインの候補や場所の位置を本物の Places API から受け取れないこと。
	PlacesUnavailable Code = "places_unavailable"
	// DailyLimit は、Places API を呼ぶ1日の上限（全体または1人あたり）に達したこと。
	// 通信できないのとは違い、もう一度試しても今日は直らないため、アプリで分けて伝える。
	DailyLimit Code = "daily_limit"
)

var statusByCode = map[Code]int{
	BadRequest:        http.StatusBadRequest,
	NotCheckedIn:      http.StatusBadRequest,
	Unauthenticated:   http.StatusUnauthorized,
	PermissionDenied:  http.StatusForbidden,
	LoginRequired:     http.StatusForbidden,
	NotFound:          http.StatusNotFound,
	PlaceNotFound:     http.StatusNotFound,
	TooFar:            http.StatusBadRequest,
	OriginNotFound:    http.StatusNotFound,
	Internal:          http.StatusInternalServerError,
	NotImplemented:    http.StatusNotImplemented,
	PlacesUnavailable: http.StatusServiceUnavailable,
	DailyLimit:        http.StatusTooManyRequests,
}

// Error はクライアントに返すエラー。Message は利用者に見せてよい日本語の文にする。
type Error struct {
	Code    Code
	Message string
	Cause   error // ログ用。レスポンスには出さない
}

func (e *Error) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %s: %v", e.Code, e.Message, e.Cause)
	}
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

func (e *Error) Unwrap() error { return e.Cause }

func (e *Error) HTTPStatus() int {
	if s, ok := statusByCode[e.Code]; ok {
		return s
	}
	return http.StatusInternalServerError
}

func New(code Code, format string, args ...any) *Error {
	return &Error{Code: code, Message: fmt.Sprintf(format, args...)}
}

func Wrap(code Code, cause error, message string) *Error {
	return &Error{Code: code, Message: message, Cause: cause}
}

// From は任意のエラーを *Error に変える。*Error でなければ internal にする。
func From(err error) *Error {
	var e *Error
	if errors.As(err, &e) {
		return e
	}
	return &Error{Code: Internal, Message: "サーバーでエラーが起きました", Cause: err}
}
