// Package auth は Firebase Auth の IDトークンを検証する。
package auth

import (
	"context"
	"errors"
	"strings"

	firebase "firebase.google.com/go/v4"
	fbauth "firebase.google.com/go/v4/auth"
)

type User struct {
	UID         string
	IsAnonymous bool
}

var ErrInvalidToken = errors.New("invalid token")

type Verifier interface {
	Verify(ctx context.Context, idToken string) (User, error)
}

// FirebaseVerifier は Firebase Admin SDK で IDトークンを検証する。
type FirebaseVerifier struct {
	client *fbauth.Client
}

func NewFirebaseVerifier(ctx context.Context, app *firebase.App) (*FirebaseVerifier, error) {
	c, err := app.Auth(ctx)
	if err != nil {
		return nil, err
	}
	return &FirebaseVerifier{client: c}, nil
}

func (v *FirebaseVerifier) Verify(ctx context.Context, idToken string) (User, error) {
	tok, err := v.client.VerifyIDToken(ctx, idToken)
	if err != nil {
		return User{}, errors.Join(ErrInvalidToken, err)
	}
	return User{
		UID:         tok.UID,
		IsAnonymous: tok.Firebase.SignInProvider == "anonymous",
	}, nil
}

// FakeVerifier はローカル開発用。トークンの文字列をそのまま uid にする。
// "anon:" で始まるトークンは匿名ユーザーとして扱う（例: "Bearer anon:alice"）。
type FakeVerifier struct{}

func (FakeVerifier) Verify(_ context.Context, idToken string) (User, error) {
	if idToken == "" {
		return User{}, ErrInvalidToken
	}
	if uid, ok := strings.CutPrefix(idToken, "anon:"); ok && uid != "" {
		return User{UID: uid, IsAnonymous: true}, nil
	}
	return User{UID: idToken}, nil
}

type ctxKey struct{}

func WithUser(ctx context.Context, u User) context.Context {
	return context.WithValue(ctx, ctxKey{}, u)
}

// FromContext は認証ミドルウェアが入れたユーザーを取り出す。
func FromContext(ctx context.Context) (User, bool) {
	u, ok := ctx.Value(ctxKey{}).(User)
	return u, ok
}
