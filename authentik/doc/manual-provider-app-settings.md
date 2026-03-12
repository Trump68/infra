# Ручная настройка провайдера и приложения в Authentik

Параметры для создания в UI (Directory → Providers, Applications) без использования blueprint.

---

## Провайдер (OpenID Connect Provider)

**Directory** → **Providers** → **Create** → **OpenID Connect Provider**.

| Поле | Значение |
|------|----------|
| **Имя** | `farmadoc_public_explicit_authentication_flow` |
| **Поток аутентификации** | default-authentication-flow (Welcome to authentik!) |
| **Поток авторизации** | default-provider-authorization-explicit-consent (Authorize Application) |
| **Тип клиента** | Публичный (Public) |
| **Перенаправляющие URI** | `http://localhost:3000/callback` |
| **Подписывающий ключ** | authentik Self-signed Certificate |
| **Срок кода доступа** | minutes=1 |
| **Срок Access токена** | hours=1 |
| **Срок Refresh токена** | days=30 |
| **Scopes** | openid, email, profile |
| **Режим субъекта (Subject)** | Хэшированный идентификатор пользователя |
| **Утверждения в id_token** | Включено |
| **Режим эмитента (Issuer)** | У каждого провайдера свой эмитент (per provider) |

После сохранения проверьте **slug** приложения/провайдера. Для приложения `farmadoc_app` JWKS и discovery:
- **URL JWKS (для Kong JWT):** `http://localhost:9000/application/o/farmadoc_app/jwks/` (с хоста); из Docker: `http://authentik-server:9000/application/o/farmadoc_app/jwks/`
- **Discovery (OIDC):** `http://localhost:9000/application/o/farmadoc_app/.well-known/openid-configuration/` (при необходимости)

---

## Приложение (Application)

**Applications** → **Create** (или Directory → Applications → Create).

| Поле | Значение |
|------|----------|
| **Имя** | `farmadoc_app` |
| **Идентификатор (slug)** | `farmadoc_app` |
| **Провайдер** | Выберите созданный провайдер «farmadoc_public_explicit_authentication_flow» |
| **Режим механизма политики** | any |

Redirect URI и параметры OAuth2 задаются у провайдера; у приложения указывается только привязка к провайдеру.

---

## Краткая сводка

| Объект | Имя / идентификатор | Redirect URI |
|--------|----------------------|--------------|
| Провайдер | `farmadoc_public_explicit_authentication_flow` | — |
| Приложение | `farmadoc_app` (имя и slug) | — |
| Провайдер → Redirect URIs | — | `http://localhost:3000/callback` |

В Kong в плагине openid-connect укажите `issuer` с **slug** этого провайдера (см. выше). После изменений: `docker compose restart kong`.
