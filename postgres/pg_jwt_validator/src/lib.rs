use jsonwebtoken::{decode, Algorithm, DecodingKey, Validation};
use pgrx::guc::{GucContext, GucFlags, GucRegistry, GucSetting};
use pgrx::prelude::*;
use serde::{Deserialize, Serialize};
use std::ffi::{c_char, CStr, CString};

::pgrx::pg_module_magic!(name, version);

// This provides the explicit type annotation needed to resolve the ambiguity
// for `GucSetting::new(None)`.
static JWT_SECRET: GucSetting<Option<CString>> = GucSetting::<Option<CString>>::new(None);

#[pg_guard]
pub extern "C-unwind" fn _PG_init() {
    // The `pgrx::cstr!` macro is not available in this version of pgrx.
    // We must create C-style strings and leak them to get a 'static lifetime.
    let name = Box::leak(CString::new("pg_jwt_validator.secret").unwrap().into_boxed_c_str());
    let short_desc = Box::leak(CString::new("The secret key for validating JWTs.").unwrap().into_boxed_c_str());
    let long_desc = Box::leak(CString::new("This secret must match the one used to sign the JWTs provided for OAuth authentication.").unwrap().into_boxed_c_str());

    GucRegistry::define_string_guc(
        name,
        short_desc,
        long_desc,
        &JWT_SECRET,
        GucContext::Userset,
        GucFlags::default(),
    );
}

#[pg_extern]
fn hello_pg_jwt_validator() -> &'static str {
    "Hello, pg_jwt_validator"
}

/// A simplified representation of JWT claims for Statbus. The `aud` claim
/// is used to carry the OAuth scope.
#[derive(Debug, Serialize, Deserialize, Clone)]
struct Claims {
    sub: String,
    email: String,
    role: String,
    exp: u64,
    iss: String,
    aud: String,
}

/// Validates a JWT token's signature and expiration.
///
/// # Arguments
///
/// * `token` - The JWT to validate.
/// * `secret` - The secret key to use for validation.
///
/// # Returns
///
/// `true` if the token is valid, `false` otherwise.
#[pg_extern]
fn validate_token(token: &str, secret: &str) -> bool {
    let decoding_key = DecodingKey::from_secret(secret.as_ref());
    // The algorithm must match the one used to sign the token.
    // Our SQL test helper uses HS256 by default.
    let mut validation = Validation::new(Algorithm::HS256);

    // We only care about expiration for now.
    validation.validate_exp = true;
    // Don't validate `nbf` (not before) unless it's present. The default is
    // false, but we're explicit.
    validation.validate_nbf = false;

    // For this simple test helper, we don't validate issuer or audience,
    // though the Claims struct requires them to be present in the token.
    validation.iss = None;
    validation.validate_aud = false;

    match decode::<Claims>(token, &decoding_key, &validation) {
        Ok(_) => true,
        Err(e) => {
            // Log the error for debugging purposes. This will show up in the PostgreSQL logs.
            pgrx::log!("Token validation failed: {}", e);
            false
        }
    }
}

/// The C-ABI function called by PostgreSQL's OAuth authentication mechanism.
/// The function name must match the `validator` option in `pg_hba.conf`.
#[no_mangle]
pub unsafe extern "C" fn pg_jwt_validator(
    token: *const c_char,
    issuer: *const c_char,
    scope: *const c_char,
    _error: *mut *mut c_char, // For now, we don't set error messages
) -> bool {
    // Basic safety checks
    if token.is_null() || issuer.is_null() || scope.is_null() {
        pgrx::warning!("pg_jwt_validator called with NULL argument");
        return false;
    }

    // Convert C strings to Rust strings
    let token_str = match CStr::from_ptr(token).to_str() {
        Ok(s) => s,
        Err(_) => {
            pgrx::warning!("Invalid UTF-8 in token");
            return false;
        }
    };
    let issuer_str = match CStr::from_ptr(issuer).to_str() {
        Ok(s) => s,
        Err(_) => {
            pgrx::warning!("Invalid UTF-8 in issuer");
            return false;
        }
    };
    let scope_str = match CStr::from_ptr(scope).to_str() {
        Ok(s) => s,
        Err(_) => {
            pgrx::warning!("Invalid UTF-8 in scope");
            return false;
        }
    };

    // Get secret from GUC
    let secret_cstring = match JWT_SECRET.get() {
        Some(s) => s,
        None => {
            pgrx::warning!("pg_jwt_validator.secret GUC is not set");
            return false;
        }
    };

    let secret = match secret_cstring.to_str() {
        Ok(s) => s,
        Err(_) => {
            pgrx::warning!("pg_jwt_validator.secret GUC contains invalid UTF-8");
            return false;
        }
    };

    let decoding_key = DecodingKey::from_secret(secret.as_bytes());
    let mut validation = Validation::new(Algorithm::HS256);
    validation.validate_exp = true;
    validation.validate_nbf = false;

    // Set issuer and audience (scope) for validation
    validation.set_issuer(&[issuer_str]);
    validation.set_audience(&[scope_str]);

    match decode::<Claims>(token_str, &decoding_key, &validation) {
        Ok(_) => true,
        Err(e) => {
            pgrx::log!("Token validation failed: {}", e);
            false
        }
    }
}

#[cfg(any(test, feature = "pg_test"))]
#[pg_schema]
mod tests {
    use pgrx::prelude::*;

    #[pg_test]
    fn test_hello_pg_jwt_validator() {
        assert_eq!("Hello, pg_jwt_validator", crate::hello_pg_jwt_validator());
    }

    /// A test-only wrapper to allow calling the C-ABI validator function from SQL.
    #[pg_extern]
    fn test_validator_wrapper(
        token: &str,
        issuer: &str,
        scope: &str,
    ) -> bool {
        unsafe {
            let token_cstr = std::ffi::CString::new(token).unwrap();
            let issuer_cstr = std::ffi::CString::new(issuer).unwrap();
            let scope_cstr = std::ffi::CString::new(scope).unwrap();

            crate::pg_jwt_validator(
                token_cstr.as_ptr(),
                issuer_cstr.as_ptr(),
                scope_cstr.as_ptr(),
                std::ptr::null_mut(),
            )
        }
    }
}

/// This module is required by `cargo pgrx test` invocations.
/// It must be visible at the root of your extension crate.
#[cfg(test)]
pub mod pg_test {
    pub fn setup(_options: Vec<&str>) {
        // perform one-off initialization when the pg_test framework starts
    }

    #[must_use]
    pub fn postgresql_conf_options() -> Vec<&'static str> {
        // return any postgresql.conf settings that are required for your tests
        vec![]
    }
}
