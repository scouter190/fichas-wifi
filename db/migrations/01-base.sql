-- ═══════════════════════════════════════════════════════════════════════
--  SISTEMA DE VENTA DE FICHAS — Esquema v7 (PostgreSQL, multiempresa)
--
--  Un solo producto, muchos comercios. Cada comercio ve exclusivamente
--  sus datos, y ese aislamiento lo garantiza la BASE mediante seguridad
--  a nivel de fila, no el código de la aplicación.
--
--  Cambios estructurales respecto del esquema v6 (SQLite, un dispositivo):
--    · Tabla `comercio` por encima de todo; `comercio_id` en cada tabla.
--    · Todos los únicos que eran globales pasan a ser POR COMERCIO.
--    · El número de orden usa una secuencia real: MAX+1 era una
--      condición de carrera con varios escritores.
--    · Tipos nativos: uuid, timestamptz, boolean, text.
--    · Se elimina lo específico de Izipay y de la sincronización.
-- ═══════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()

-- ─────────────────────────────────────────────────────────────────────
--  Dominios: tipos con su regla incorporada, para no repetir CHECKs
-- ─────────────────────────────────────────────────────────────────────

-- Dinero SIEMPRE en céntimos enteros. Nunca decimales: sumar 0,1 + 0,2
-- da 0,30000000000000004, y en un cierre de caja eso es un descuadre
-- imposible de explicar.
CREATE DOMAIN centimos AS integer;
CREATE DOMAIN centimos_pos AS integer CHECK (VALUE > 0);
CREATE DOMAIN centimos_nonneg AS integer CHECK (VALUE >= 0);

-- Celular peruano: 9 dígitos que empiezan en 9.
CREATE DOMAIN celular_pe AS text CHECK (VALUE ~ '^9[0-9]{8}$');

-- ─────────────────────────────────────────────────────────────────────
--  Contexto de la petición
--
--  La aplicación declara, al abrir cada transacción, qué comercio está
--  operando:   SET LOCAL app.comercio_id = '...';
--  Las políticas de seguridad leen ese valor. LOCAL significa que dura
--  solo la transacción: una conexión reutilizada no arrastra el
--  comercio anterior.
-- ─────────────────────────────────────────────────────────────────────

CREATE FUNCTION app_comercio() RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.comercio_id', true), '')::uuid
$$;

-- Marca de tiempo del servidor. Una sola fuente: el reloj del celular
-- o del navegador no decide cuándo ocurrió una venta.
CREATE FUNCTION ahora() RETURNS timestamptz
LANGUAGE sql STABLE AS $$ SELECT clock_timestamp() $$;


-- ═══════════════════════════════════════════════════════════════════════
--  COMERCIO — la raíz del modelo multiempresa
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE comercio (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          text NOT NULL CHECK (length(btrim(nombre)) BETWEEN 1 AND 120),

    -- Identificador corto para la URL del portal: /acme
    slug            text NOT NULL UNIQUE
                    CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$'),

    ruc             text CHECK (ruc IS NULL OR ruc ~ '^[0-9]{11}$'),
    plan_suscripcion text NOT NULL DEFAULT 'basico'
                    CHECK (plan_suscripcion IN ('basico','pro','enterprise')),

    -- Suspender un comercio moroso sin borrar su historia.
    activo          boolean NOT NULL DEFAULT true,
    suspendido_en   timestamptz,

    creado_en       timestamptz NOT NULL DEFAULT ahora(),

    CHECK (activo OR suspendido_en IS NOT NULL)
);

COMMENT ON TABLE comercio IS
'Cada negocio que usa el sistema. Toda fila de toda tabla pertenece a uno.';


-- ═══════════════════════════════════════════════════════════════════════
--  CONFIGURACIÓN
-- ═══════════════════════════════════════════════════════════════════════

-- Un punto de venta físico. Un comercio puede tener varios.
--
-- En v6 esta tabla tenía UNA sola fila, forzada con un truco. Ahora son
-- una o varias por comercio, así que el truco desaparece.
CREATE TABLE punto (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id        uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,

    nombre             text NOT NULL CHECK (length(btrim(nombre)) BETWEEN 1 AND 80),

    -- Prefijo de los códigos de ficha: LIMA01-A7K3M
    prefijo            text NOT NULL CHECK (prefijo ~ '^[A-Z0-9]{2,8}$'),

    tipo               text NOT NULL DEFAULT 'fijo' CHECK (tipo IN ('fijo','movil')),

    -- La usa la aplicación para calcular la fecha local de cada venta.
    zona_horaria       text NOT NULL DEFAULT 'America/Lima',

    reserva_ttl_min    integer NOT NULL DEFAULT 10
                       CHECK (reserva_ttl_min BETWEEN 2 AND 60),
    pool_minimo        integer NOT NULL DEFAULT 20 CHECK (pool_minimo >= 0),
    umbral_manual      integer NOT NULL DEFAULT 5 CHECK (umbral_manual >= 0),
    umbral_descuadre   centimos_nonneg NOT NULL DEFAULT 200,

    -- Formato exacto de la referencia del voucher del POS, como
    -- expresión regular. NULL = solo rige la validación general.
    ref_patron_pos     text,

    activo             boolean NOT NULL DEFAULT true,
    creado_en          timestamptz NOT NULL DEFAULT ahora(),

    -- El prefijo identifica al punto dentro del comercio: no se repite.
    UNIQUE (comercio_id, prefijo),
    UNIQUE (comercio_id, nombre),
    -- Permite que las claves foráneas compuestas verifiquen el comercio.
    UNIQUE (id, comercio_id)
);

CREATE INDEX ON punto (comercio_id) WHERE activo;


-- El catálogo: qué se vende.
CREATE TABLE plan (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id       uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,

    -- Código legible que además es el nombre del PERFIL EN EL ROUTER.
    -- Por eso se repite entre comercios, pero no dentro de uno.
    codigo            text NOT NULL CHECK (codigo ~ '^[A-Za-z0-9_]{2,20}$'),
    nombre            text NOT NULL CHECK (length(btrim(nombre)) BETWEEN 1 AND 60),

    -- Pestaña del catálogo en pantalla.
    categoria         text NOT NULL DEFAULT 'tiempo'
                      CHECK (categoria IN ('tiempo','datos','mixto')),

    orden_display     integer NOT NULL DEFAULT 0,
    precio_centimos   centimos_pos NOT NULL,

    limite_tiempo_seg integer CHECK (limite_tiempo_seg IS NULL OR limite_tiempo_seg > 0),
    limite_bytes      bigint  CHECK (limite_bytes IS NULL OR limite_bytes > 0),

    -- Plazo para consumir la cuota, desde el primer uso. NO es lo mismo
    -- que el tiempo de navegación: 3 horas válidas por 7 días.
    validez_dias      integer NOT NULL CHECK (validez_dias > 0),
    rate_limit        text NOT NULL,          -- formato RouterOS: '3M/1M'

    -- Umbral de reposición propio. Un mínimo único para todo el punto no
    -- encaja: la ficha de un día se vende 40 veces al día y la semanal 2.
    -- NULL = usar punto.pool_minimo.
    stock_minimo      integer CHECK (stock_minimo IS NULL OR stock_minimo >= 0),

    activo            boolean NOT NULL DEFAULT true,
    creado_en         timestamptz NOT NULL DEFAULT ahora(),

    UNIQUE (comercio_id, codigo),
    UNIQUE (id, comercio_id),

    -- Ningún plan sin límite: sería acceso ilimitado por descuido.
    CHECK (limite_tiempo_seg IS NOT NULL OR limite_bytes IS NOT NULL),
    -- La categoría debe ser coherente con los límites declarados.
    CHECK (categoria <> 'tiempo' OR limite_tiempo_seg IS NOT NULL),
    CHECK (categoria <> 'datos'  OR limite_bytes      IS NOT NULL),
    CHECK (categoria <> 'mixto'  OR (limite_tiempo_seg IS NOT NULL
                                 AND limite_bytes      IS NOT NULL))
);

CREATE INDEX ON plan (comercio_id, orden_display) WHERE activo;


-- ═══════════════════════════════════════════════════════════════════════
--  PERSONAS
-- ═══════════════════════════════════════════════════════════════════════

-- Quien entra al portal. Antes era `operario` con un PIN en un celular;
-- ahora es una cuenta expuesta a internet, con correo y contraseña.
CREATE TABLE usuario (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id       uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,

    nombre            text NOT NULL CHECK (length(btrim(nombre)) BETWEEN 1 AND 80),

    -- Se guarda en minúsculas para que Rosa@ y rosa@ no sean dos cuentas.
    email             text NOT NULL CHECK (email = lower(email) AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),

    password_hash     text NOT NULL,          -- Argon2id o bcrypt; NUNCA en claro
    rol               text NOT NULL DEFAULT 'operario'
                      CHECK (rol IN ('operario','supervisor','admin')),

    intentos_fallidos integer NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0),
    bloqueado_hasta   timestamptz,
    ultimo_acceso     timestamptz,

    activo            boolean NOT NULL DEFAULT true,
    creado_en         timestamptz NOT NULL DEFAULT ahora(),

    -- ⚠ CORRECCIÓN v7: en v6 el usuario era único GLOBAL. Con varios
    -- comercios, si uno registraba "rosa@...", ningún otro podría.
    UNIQUE (comercio_id, email),
    UNIQUE (id, comercio_id)
);

CREATE INDEX ON usuario (comercio_id) WHERE activo;

-- El correo sí es único en todo el sistema: es la llave de acceso al
-- portal, y una persona no puede pertenecer a dos comercios con el
-- mismo correo sin volver ambiguo el ingreso.
CREATE UNIQUE INDEX usuario_email_global ON usuario (email) WHERE activo;


-- Un periodo de trabajo con una caja. Sin turnos, las diferencias de
-- caja no tienen responsable.
CREATE TABLE turno (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id         uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    punto_id            uuid NOT NULL,
    usuario_id          uuid NOT NULL,

    -- Día al que se imputa el turno. NO es la fecha de las ventas: un
    -- turno de 18:00 a 02:00 cruza dos fechas pero es un solo día.
    dia_operativo       date NOT NULL,

    abierto_en          timestamptz NOT NULL DEFAULT ahora(),
    cerrado_en          timestamptz,

    fondo_inicial       centimos_nonneg NOT NULL DEFAULT 0,
    efectivo_declarado  centimos_nonneg,
    efectivo_esperado   centimos,
    diferencia          centimos,
    nota_cierre         text,

    FOREIGN KEY (punto_id, comercio_id)   REFERENCES punto (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id) REFERENCES usuario (id, comercio_id),

    -- Cierre y conteo van juntos: o ambos vacíos, o ambos llenos.
    CHECK ((cerrado_en IS NULL) = (efectivo_declarado IS NULL)),
    CHECK (cerrado_en IS NULL OR cerrado_en >= abierto_en),
    UNIQUE (id, comercio_id)
);

-- ⚠ CORRECCIÓN v7: en SQLite un índice único sobre una columna nula no
-- restringe nada, y hubo que inventar una columna constante `solo_uno`.
-- PostgreSQL indexa `punto_id` (nunca nulo) filtrando los abiertos, así
-- que el truco desaparece. Y ahora el límite es UN TURNO POR PUNTO, no
-- uno por sistema: un comercio con dos puntos opera los dos a la vez.
CREATE UNIQUE INDEX turno_uno_abierto_por_punto
    ON turno (punto_id) WHERE cerrado_en IS NULL;

CREATE INDEX ON turno (comercio_id, dia_operativo);


-- Movimientos de efectivo que no son ventas: retiros, ingresos de
-- cambio, ajustes. Sin esto, ese dinero aparecería como descuadre.
CREATE TABLE movimiento_caja (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id     uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    turno_id        uuid NOT NULL,
    usuario_id      uuid NOT NULL,

    tipo            text NOT NULL CHECK (tipo IN ('fondo','retiro','ingreso','ajuste')),
    monto_centimos  centimos NOT NULL CHECK (monto_centimos <> 0),
    motivo          text NOT NULL CHECK (length(btrim(motivo)) > 0),
    ocurrido_en     timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (turno_id, comercio_id)   REFERENCES turno (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id) REFERENCES usuario (id, comercio_id)
);

CREATE INDEX ON movimiento_caja (turno_id);


-- Registrar al cliente es OPCIONAL: si fuera obligatorio, la cola se
-- alarga y la gente se va.
CREATE TABLE cliente (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id       uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,

    celular           celular_pe NOT NULL,
    nombre            text,
    apellido          text,
    email             text CHECK (email IS NULL OR email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),

    documento_tipo    text CHECK (documento_tipo IN ('DNI','CE','PASAPORTE','RUC')),
    documento_num     text,

    -- Sin consentimiento registrado, el dato no debe existir. Por eso es
    -- obligatorio: la aplicación no puede olvidarlo.
    consentimiento_en timestamptz NOT NULL,

    activo            boolean NOT NULL DEFAULT true,
    creado_en         timestamptz NOT NULL DEFAULT ahora(),

    -- ⚠ CORRECCIÓN v7: el celular era único GLOBAL. Una misma persona
    -- puede ser cliente de dos comercios distintos.
    UNIQUE (comercio_id, celular),
    UNIQUE (id, comercio_id),

    CHECK ((documento_tipo IS NULL) = (documento_num IS NULL)),
    CHECK (documento_tipo IS DISTINCT FROM 'DNI' OR documento_num ~ '^[0-9]{8}$')
);
