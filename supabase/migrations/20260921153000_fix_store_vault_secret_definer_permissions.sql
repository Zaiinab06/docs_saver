-- Avoid requiring UPDATE privilege on vault.secrets from the public helper definer.
-- The advisory lock serializes this helper by secret name; Vault owns updates.
CREATE OR REPLACE FUNCTION public.store_vault_secret(
    new_secret TEXT,
    new_name TEXT DEFAULT NULL,
    new_description TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    secret_id UUID;
BEGIN
    IF new_name IS NULL OR new_name = '' THEN
        SELECT vault.create_secret(
            new_secret,
            new_name,
            new_description,
            NULL::UUID
        )
        INTO secret_id;

        RETURN secret_id;
    END IF;

    -- Serialize callbacks for the same logical Vault secret name.
    PERFORM pg_advisory_xact_lock(hashtextextended(new_name, 0));

    SELECT id
    INTO secret_id
    FROM vault.secrets
    WHERE name = new_name;

    IF secret_id IS NOT NULL THEN
        PERFORM vault.update_secret(
            secret_id,
            new_secret,
            new_name,
            new_description,
            NULL::UUID
        );

        RETURN secret_id;
    END IF;

    BEGIN
        SELECT vault.create_secret(
            new_secret,
            new_name,
            new_description,
            NULL::UUID
        )
        INTO secret_id;
    EXCEPTION
        WHEN unique_violation THEN
            -- Recover if another writer created this name without the advisory lock.
            SELECT id
            INTO secret_id
            FROM vault.secrets
            WHERE name = new_name;

            IF secret_id IS NULL THEN
                RAISE;
            END IF;

            PERFORM vault.update_secret(
                secret_id,
                new_secret,
                new_name,
                new_description,
                NULL::UUID
            );
    END;

    RETURN secret_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.store_vault_secret(TEXT, TEXT, TEXT)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.store_vault_secret(TEXT, TEXT, TEXT)
TO service_role;
