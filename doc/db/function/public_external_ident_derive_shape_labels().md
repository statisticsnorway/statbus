```sql
CREATE OR REPLACE FUNCTION public.external_ident_derive_shape_labels()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    _shape external_ident_shape;
    _labels LTREE;
    _type_code TEXT;
BEGIN
    -- Get shape, labels, and code from type for validation
    SELECT shape, labels, code INTO _shape, _labels, _type_code
    FROM public.external_ident_type 
    WHERE id = NEW.type_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid type_id: %', NEW.type_id;
    END IF;
    
    -- Set denormalized fields
    NEW.shape := _shape;
    
    IF _shape = 'hierarchical' THEN
        NEW.labels := _labels;
        
        -- Validate user provided correct fields
        IF NEW.idents IS NULL THEN
            RAISE EXCEPTION 'Hierarchical identifier type "%" requires idents (ltree), not ident', _type_code;
        END IF;
        IF NEW.ident IS NOT NULL THEN
            RAISE EXCEPTION 'Hierarchical identifier type "%" cannot use ident field, use idents instead', _type_code;
        END IF;
    ELSE -- regular
        NEW.labels := NULL;
        
        -- Validate user provided correct fields  
        IF NEW.ident IS NULL THEN
            RAISE EXCEPTION 'Regular identifier type "%" requires ident (text), not idents', _type_code;
        END IF;
        IF NEW.idents IS NOT NULL THEN
            RAISE EXCEPTION 'Regular identifier type "%" cannot use idents field, use ident instead', _type_code;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$function$
```
