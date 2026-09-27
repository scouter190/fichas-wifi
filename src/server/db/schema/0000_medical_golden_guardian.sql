-- Current sql file was generated after introspecting the database
-- If you want to run this migration please uncomment this code before executing migrations
/*
CREATE TABLE "comercio" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"nombre" text NOT NULL,
	"slug" text NOT NULL,
	"ruc" text,
	"plan_suscripcion" text DEFAULT 'basico' NOT NULL,
	"activo" boolean DEFAULT true NOT NULL,
	"suspendido_en" timestamp with time zone,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "comercio_check" CHECK (activo OR (suspendido_en IS NOT NULL)),
	CONSTRAINT "comercio_nombre_check" CHECK ((length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 120)),
	CONSTRAINT "comercio_plan_suscripcion_check" CHECK (plan_suscripcion = ANY (ARRAY['basico'::text, 'pro'::text, 'enterprise'::text])),
	CONSTRAINT "comercio_ruc_check" CHECK ((ruc IS NULL) OR (ruc ~ '^[0-9]{11}$'::text)),
	CONSTRAINT "comercio_slug_check" CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$'::text)
);
--> statement-breakpoint
CREATE TABLE "punto" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"nombre" text NOT NULL,
	"prefijo" text NOT NULL,
	"tipo" text DEFAULT 'fijo' NOT NULL,
	"zona_horaria" text DEFAULT 'America/Lima' NOT NULL,
	"reserva_ttl_min" integer DEFAULT 10 NOT NULL,
	"pool_minimo" integer DEFAULT 20 NOT NULL,
	"umbral_manual" integer DEFAULT 5 NOT NULL,
	"umbral_descuadre" "centimos_nonneg" DEFAULT 200 NOT NULL,
	"ref_patron_pos" text,
	"activo" boolean DEFAULT true NOT NULL,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "punto_nombre_check" CHECK ((length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 80)),
	CONSTRAINT "punto_pool_minimo_check" CHECK (pool_minimo >= 0),
	CONSTRAINT "punto_prefijo_check" CHECK (prefijo ~ '^[A-Z0-9]{2,8}$'::text),
	CONSTRAINT "punto_reserva_ttl_min_check" CHECK ((reserva_ttl_min >= 2) AND (reserva_ttl_min <= 60)),
	CONSTRAINT "punto_tipo_check" CHECK (tipo = ANY (ARRAY['fijo'::text, 'movil'::text])),
	CONSTRAINT "punto_umbral_manual_check" CHECK (umbral_manual >= 0)
);
--> statement-breakpoint
ALTER TABLE "punto" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "contador_orden" (
	"comercio_id" uuid NOT NULL,
	"siguiente" bigint DEFAULT 1 NOT NULL,
	CONSTRAINT "contador_orden_siguiente_check" CHECK (siguiente > 0)
);
--> statement-breakpoint
CREATE TABLE "importacion" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"punto_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"archivo" text NOT NULL,
	"huella" text NOT NULL,
	"filas_leidas" integer NOT NULL,
	"filas_nuevas" integer NOT NULL,
	"en_router_al_importar" boolean NOT NULL,
	"importado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "importacion_check" CHECK (filas_nuevas <= filas_leidas),
	CONSTRAINT "importacion_filas_leidas_check" CHECK (filas_leidas >= 0),
	CONSTRAINT "importacion_filas_nuevas_check" CHECK (filas_nuevas > 0)
);
--> statement-breakpoint
ALTER TABLE "importacion" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "pago" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"orden_id" uuid NOT NULL,
	"metodo" text NOT NULL,
	"motivo_manual" text,
	"medio" text,
	"referencia" text,
	"estado" text DEFAULT 'pendiente' NOT NULL,
	"monto_centimos" "centimos_pos" NOT NULL,
	"recibido_centimos" "centimos_pos",
	"confirmado_por" uuid,
	"detalle" text,
	"conciliado_en" timestamp with time zone,
	"conciliado_por" uuid,
	"devuelto_en" timestamp with time zone,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	"resuelto_en" timestamp with time zone,
	CONSTRAINT "pago_check" CHECK ((metodo <> 'efectivo'::text) OR ((referencia IS NULL) AND (motivo_manual IS NULL) AND (medio IS NULL))),
	CONSTRAINT "pago_check1" CHECK ((recibido_centimos IS NULL) OR ((metodo = 'efectivo'::text) AND ((recibido_centimos)::integer >= (monto_centimos)::integer))),
	CONSTRAINT "pago_check2" CHECK ((metodo <> 'manual'::text) OR (motivo_manual IS NOT NULL)),
	CONSTRAINT "pago_check3" CHECK ((motivo_manual IS DISTINCT FROM 'pos_externo'::text) OR ((medio IS NOT NULL) AND (referencia ~ '^[A-Za-z0-9]{4,20}$'::text))),
	CONSTRAINT "pago_check4" CHECK ((conciliado_en IS NULL) = (conciliado_por IS NULL)),
	CONSTRAINT "pago_check5" CHECK ((conciliado_en IS NULL) OR ((metodo = 'manual'::text) AND (estado = ANY (ARRAY['exitoso'::text, 'devuelto'::text])))),
	CONSTRAINT "pago_check6" CHECK ((estado = 'devuelto'::text) = (devuelto_en IS NOT NULL)),
	CONSTRAINT "pago_check7" CHECK ((estado = 'pendiente'::text) = (resuelto_en IS NULL)),
	CONSTRAINT "pago_estado_check" CHECK (estado = ANY (ARRAY['pendiente'::text, 'exitoso'::text, 'fallido'::text, 'expirado'::text, 'devuelto'::text])),
	CONSTRAINT "pago_medio_check" CHECK (medio = ANY (ARRAY['QR'::text, 'YAPE'::text, 'PLIN'::text, 'CARD'::text, 'TRANSFERENCIA'::text])),
	CONSTRAINT "pago_metodo_check" CHECK (metodo = ANY (ARRAY['efectivo'::text, 'manual'::text])),
	CONSTRAINT "pago_motivo_manual_check" CHECK (motivo_manual = ANY (ARRAY['pos_externo'::text, 'sin_internet'::text, 'cuenta_personal'::text, 'monto_distinto'::text, 'otro'::text]))
);
--> statement-breakpoint
ALTER TABLE "pago" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "incidencia" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"turno_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"orden_id" uuid,
	"tipo" text NOT NULL,
	"descripcion" text NOT NULL,
	"referencia" text,
	"celular" text,
	"monto_centimos" "centimos",
	"estado" text DEFAULT 'abierta' NOT NULL,
	"resuelto_por" uuid,
	"resolucion" text,
	"resuelto_en" timestamp with time zone,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "incidencia_check" CHECK ((estado = 'abierta'::text) = (resuelto_en IS NULL)),
	CONSTRAINT "incidencia_descripcion_check" CHECK (length(btrim(descripcion)) > 0),
	CONSTRAINT "incidencia_estado_check" CHECK (estado = ANY (ARRAY['abierta'::text, 'resuelta'::text, 'descartada'::text])),
	CONSTRAINT "incidencia_tipo_check" CHECK (tipo = ANY (ARRAY['pago_no_verificable'::text, 'monto_incorrecto'::text, 'ficha_no_funciona'::text, 'sin_respaldo_pos'::text, 'otro'::text]))
);
--> statement-breakpoint
ALTER TABLE "incidencia" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "plan" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"codigo" text NOT NULL,
	"nombre" text NOT NULL,
	"categoria" text DEFAULT 'tiempo' NOT NULL,
	"orden_display" integer DEFAULT 0 NOT NULL,
	"precio_centimos" "centimos_pos" NOT NULL,
	"limite_tiempo_seg" integer,
	"limite_bytes" bigint,
	"validez_dias" integer NOT NULL,
	"rate_limit" text NOT NULL,
	"stock_minimo" integer,
	"activo" boolean DEFAULT true NOT NULL,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "plan_categoria_check" CHECK (categoria = ANY (ARRAY['tiempo'::text, 'datos'::text, 'mixto'::text])),
	CONSTRAINT "plan_check" CHECK ((limite_tiempo_seg IS NOT NULL) OR (limite_bytes IS NOT NULL)),
	CONSTRAINT "plan_check1" CHECK ((categoria <> 'tiempo'::text) OR (limite_tiempo_seg IS NOT NULL)),
	CONSTRAINT "plan_check2" CHECK ((categoria <> 'datos'::text) OR (limite_bytes IS NOT NULL)),
	CONSTRAINT "plan_check3" CHECK ((categoria <> 'mixto'::text) OR ((limite_tiempo_seg IS NOT NULL) AND (limite_bytes IS NOT NULL))),
	CONSTRAINT "plan_codigo_check" CHECK (codigo ~ '^[A-Za-z0-9_]{2,20}$'::text),
	CONSTRAINT "plan_limite_bytes_check" CHECK ((limite_bytes IS NULL) OR (limite_bytes > 0)),
	CONSTRAINT "plan_limite_tiempo_seg_check" CHECK ((limite_tiempo_seg IS NULL) OR (limite_tiempo_seg > 0)),
	CONSTRAINT "plan_nombre_check" CHECK ((length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 60)),
	CONSTRAINT "plan_stock_minimo_check" CHECK ((stock_minimo IS NULL) OR (stock_minimo >= 0)),
	CONSTRAINT "plan_validez_dias_check" CHECK (validez_dias > 0)
);
--> statement-breakpoint
ALTER TABLE "plan" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "usuario" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"nombre" text NOT NULL,
	"email" text NOT NULL,
	"password_hash" text NOT NULL,
	"rol" text DEFAULT 'operario' NOT NULL,
	"intentos_fallidos" integer DEFAULT 0 NOT NULL,
	"bloqueado_hasta" timestamp with time zone,
	"ultimo_acceso" timestamp with time zone,
	"activo" boolean DEFAULT true NOT NULL,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "usuario_email_check" CHECK ((email = lower(email)) AND (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text)),
	CONSTRAINT "usuario_intentos_fallidos_check" CHECK (intentos_fallidos >= 0),
	CONSTRAINT "usuario_nombre_check" CHECK ((length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 80)),
	CONSTRAINT "usuario_rol_check" CHECK (rol = ANY (ARRAY['operario'::text, 'supervisor'::text, 'admin'::text]))
);
--> statement-breakpoint
ALTER TABLE "usuario" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "turno" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"punto_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"dia_operativo" date NOT NULL,
	"abierto_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	"cerrado_en" timestamp with time zone,
	"fondo_inicial" "centimos_nonneg" DEFAULT 0 NOT NULL,
	"efectivo_declarado" "centimos_nonneg",
	"efectivo_esperado" "centimos",
	"diferencia" "centimos",
	"nota_cierre" text,
	CONSTRAINT "turno_check" CHECK ((cerrado_en IS NULL) = (efectivo_declarado IS NULL)),
	CONSTRAINT "turno_check1" CHECK ((cerrado_en IS NULL) OR (cerrado_en >= abierto_en))
);
--> statement-breakpoint
ALTER TABLE "turno" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "movimiento_caja" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"turno_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"tipo" text NOT NULL,
	"monto_centimos" "centimos" NOT NULL,
	"motivo" text NOT NULL,
	"ocurrido_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "movimiento_caja_monto_centimos_check" CHECK ((monto_centimos)::integer <> 0),
	CONSTRAINT "movimiento_caja_motivo_check" CHECK (length(btrim(motivo)) > 0),
	CONSTRAINT "movimiento_caja_tipo_check" CHECK (tipo = ANY (ARRAY['fondo'::text, 'retiro'::text, 'ingreso'::text, 'ajuste'::text]))
);
--> statement-breakpoint
ALTER TABLE "movimiento_caja" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "cliente" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"celular" "celular_pe" NOT NULL,
	"nombre" text,
	"apellido" text,
	"email" text,
	"documento_tipo" text,
	"documento_num" text,
	"consentimiento_en" timestamp with time zone NOT NULL,
	"activo" boolean DEFAULT true NOT NULL,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "cliente_check" CHECK ((documento_tipo IS NULL) = (documento_num IS NULL)),
	CONSTRAINT "cliente_check1" CHECK ((documento_tipo IS DISTINCT FROM 'DNI'::text) OR (documento_num ~ '^[0-9]{8}$'::text)),
	CONSTRAINT "cliente_documento_tipo_check" CHECK (documento_tipo = ANY (ARRAY['DNI'::text, 'CE'::text, 'PASAPORTE'::text, 'RUC'::text])),
	CONSTRAINT "cliente_email_check" CHECK ((email IS NULL) OR (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text))
);
--> statement-breakpoint
ALTER TABLE "cliente" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "lote" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"punto_id" uuid NOT NULL,
	"plan_id" uuid NOT NULL,
	"importacion_id" uuid,
	"cantidad" integer NOT NULL,
	"impreso_en" timestamp with time zone,
	"anulado_en" timestamp with time zone,
	"motivo_anulacion" text,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "lote_cantidad_check" CHECK (cantidad > 0),
	CONSTRAINT "lote_check" CHECK ((anulado_en IS NULL) = (motivo_anulacion IS NULL))
);
--> statement-breakpoint
ALTER TABLE "lote" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "ficha" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"punto_id" uuid NOT NULL,
	"lote_id" uuid NOT NULL,
	"plan_id" uuid NOT NULL,
	"codigo" text NOT NULL,
	"origen" text DEFAULT 'importada' NOT NULL,
	"estado" text DEFAULT 'disponible' NOT NULL,
	"en_router" boolean DEFAULT false NOT NULL,
	"router_conf_en" timestamp with time zone,
	"reservada_hasta" timestamp with time zone,
	"vendida_en" timestamp with time zone,
	"primer_login_en" timestamp with time zone,
	"expira_en" timestamp with time zone,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "ficha_check" CHECK (en_router = (router_conf_en IS NOT NULL)),
	CONSTRAINT "ficha_check1" CHECK ((estado <> 'reservada'::text) OR (reservada_hasta IS NOT NULL)),
	CONSTRAINT "ficha_check2" CHECK ((estado <> ALL (ARRAY['vendida'::text, 'activada'::text, 'agotada'::text, 'expirada'::text])) OR (vendida_en IS NOT NULL)),
	CONSTRAINT "ficha_check3" CHECK ((estado <> ALL (ARRAY['activada'::text, 'agotada'::text])) OR (primer_login_en IS NOT NULL)),
	CONSTRAINT "ficha_codigo_check" CHECK (codigo ~ '^[A-Z0-9]{2,8}-[A-HJ-NP-Z2-9]{4,12}$'::text),
	CONSTRAINT "ficha_estado_check" CHECK (estado = ANY (ARRAY['disponible'::text, 'reservada'::text, 'vendida'::text, 'activada'::text, 'agotada'::text, 'expirada'::text, 'anulada'::text])),
	CONSTRAINT "ficha_origen_check" CHECK (origen = ANY (ARRAY['app'::text, 'importada'::text]))
);
--> statement-breakpoint
ALTER TABLE "ficha" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "orden" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"turno_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"ficha_id" uuid NOT NULL,
	"plan_id" uuid NOT NULL,
	"cliente_id" uuid,
	"numero" bigint,
	"monto_centimos" "centimos_pos" NOT NULL,
	"estado" text DEFAULT 'abierta' NOT NULL,
	"expira_en" timestamp with time zone NOT NULL,
	"creado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	"resuelta_en" timestamp with time zone,
	CONSTRAINT "orden_check" CHECK ((estado = 'abierta'::text) = (resuelta_en IS NULL)),
	CONSTRAINT "orden_estado_check" CHECK (estado = ANY (ARRAY['abierta'::text, 'pagada'::text, 'cancelada'::text, 'expirada'::text]))
);
--> statement-breakpoint
ALTER TABLE "orden" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "venta" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"turno_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"ficha_id" uuid NOT NULL,
	"orden_id" uuid NOT NULL,
	"plan_id" uuid NOT NULL,
	"cliente_id" uuid,
	"metodo" text NOT NULL,
	"monto_centimos" "centimos_pos" NOT NULL,
	"fecha_local" date NOT NULL,
	"hora_local" smallint NOT NULL,
	"comprobante_id" text,
	"ocurrida_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "venta_hora_local_check" CHECK ((hora_local >= 0) AND (hora_local <= 23)),
	CONSTRAINT "venta_metodo_check" CHECK (metodo = ANY (ARRAY['efectivo'::text, 'manual'::text]))
);
--> statement-breakpoint
ALTER TABLE "venta" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "anulacion" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"venta_id" uuid NOT NULL,
	"turno_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"motivo" text NOT NULL,
	"detalle" text,
	"ocurrida_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "anulacion_motivo_check" CHECK (motivo = ANY (ARRAY['error_operario'::text, 'ficha_no_funciona'::text, 'reclamo_cliente'::text, 'devolucion_pos'::text, 'otro'::text]))
);
--> statement-breakpoint
ALTER TABLE "anulacion" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "entrega" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"venta_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"medio" text NOT NULL,
	"reimpresion" boolean DEFAULT false NOT NULL,
	"motivo" text,
	"ocurrido_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "entrega_check" CHECK ((NOT reimpresion) OR (motivo IS NOT NULL)),
	CONSTRAINT "entrega_medio_check" CHECK (medio = ANY (ARRAY['pantalla'::text, 'impresa'::text]))
);
--> statement-breakpoint
ALTER TABLE "entrega" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "intento_venta" (
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"comercio_id" uuid NOT NULL,
	"turno_id" uuid NOT NULL,
	"usuario_id" uuid NOT NULL,
	"plan_id" uuid,
	"resultado" text NOT NULL,
	"nota" text,
	"venta_id" uuid,
	"fecha_local" date NOT NULL,
	"hora_local" smallint NOT NULL,
	"ocurrido_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "intento_venta_check" CHECK ((resultado = 'vendida'::text) = (venta_id IS NOT NULL)),
	CONSTRAINT "intento_venta_hora_local_check" CHECK ((hora_local >= 0) AND (hora_local <= 23)),
	CONSTRAINT "intento_venta_resultado_check" CHECK (resultado = ANY (ARRAY['vendida'::text, 'sin_stock'::text, 'desistio'::text, 'precio'::text, 'sin_servicio'::text, 'sin_cambio'::text, 'otro'::text]))
);
--> statement-breakpoint
ALTER TABLE "intento_venta" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "stock_cierre" (
	"comercio_id" uuid NOT NULL,
	"turno_id" uuid NOT NULL,
	"plan_id" uuid NOT NULL,
	"disponibles" integer NOT NULL,
	"sin_cargar" integer NOT NULL,
	"minimo" integer NOT NULL,
	"registrado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "stock_cierre_disponibles_check" CHECK (disponibles >= 0),
	CONSTRAINT "stock_cierre_sin_cargar_check" CHECK (sin_cargar >= 0)
);
--> statement-breakpoint
ALTER TABLE "stock_cierre" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "consumo" (
	"ficha_id" uuid NOT NULL,
	"comercio_id" uuid NOT NULL,
	"bytes_in" bigint DEFAULT 0 NOT NULL,
	"bytes_out" bigint DEFAULT 0 NOT NULL,
	"uptime_seg" bigint DEFAULT 0 NOT NULL,
	"sesiones" integer DEFAULT 0 NOT NULL,
	"actualizado_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "consumo_bytes_in_check" CHECK (bytes_in >= 0),
	CONSTRAINT "consumo_bytes_out_check" CHECK (bytes_out >= 0),
	CONSTRAINT "consumo_sesiones_check" CHECK (sesiones >= 0),
	CONSTRAINT "consumo_uptime_seg_check" CHECK (uptime_seg >= 0)
);
--> statement-breakpoint
ALTER TABLE "consumo" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "auditoria" (
	"id" bigserial NOT NULL,
	"comercio_id" uuid NOT NULL,
	"usuario_id" uuid,
	"entidad" text NOT NULL,
	"entidad_id" uuid NOT NULL,
	"accion" text NOT NULL,
	"datos" jsonb,
	"ocurrido_en" timestamp with time zone DEFAULT ahora() NOT NULL,
	CONSTRAINT "auditoria_accion_check" CHECK (accion = ANY (ARRAY['crear'::text, 'actualizar'::text, 'anular'::text]))
);
--> statement-breakpoint
ALTER TABLE "auditoria" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "punto" ADD CONSTRAINT "punto_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "contador_orden" ADD CONSTRAINT "contador_orden_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "importacion" ADD CONSTRAINT "importacion_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "importacion" ADD CONSTRAINT "importacion_punto_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","punto_id") REFERENCES "public"."punto"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "importacion" ADD CONSTRAINT "importacion_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pago" ADD CONSTRAINT "pago_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pago" ADD CONSTRAINT "pago_conciliado_por_comercio_id_fkey" FOREIGN KEY ("comercio_id","conciliado_por") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pago" ADD CONSTRAINT "pago_confirmado_por_comercio_id_fkey" FOREIGN KEY ("comercio_id","confirmado_por") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pago" ADD CONSTRAINT "pago_orden_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","orden_id") REFERENCES "public"."orden"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "incidencia" ADD CONSTRAINT "incidencia_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "incidencia" ADD CONSTRAINT "incidencia_orden_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","orden_id") REFERENCES "public"."orden"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "incidencia" ADD CONSTRAINT "incidencia_resuelto_por_comercio_id_fkey" FOREIGN KEY ("comercio_id","resuelto_por") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "incidencia" ADD CONSTRAINT "incidencia_turno_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","turno_id") REFERENCES "public"."turno"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "incidencia" ADD CONSTRAINT "incidencia_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan" ADD CONSTRAINT "plan_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "usuario" ADD CONSTRAINT "usuario_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "turno" ADD CONSTRAINT "turno_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "turno" ADD CONSTRAINT "turno_punto_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","punto_id") REFERENCES "public"."punto"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "turno" ADD CONSTRAINT "turno_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "movimiento_caja" ADD CONSTRAINT "movimiento_caja_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "movimiento_caja" ADD CONSTRAINT "movimiento_caja_turno_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","turno_id") REFERENCES "public"."turno"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "movimiento_caja" ADD CONSTRAINT "movimiento_caja_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "cliente" ADD CONSTRAINT "cliente_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lote" ADD CONSTRAINT "lote_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lote" ADD CONSTRAINT "lote_importacion_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","importacion_id") REFERENCES "public"."importacion"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lote" ADD CONSTRAINT "lote_plan_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","plan_id") REFERENCES "public"."plan"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lote" ADD CONSTRAINT "lote_punto_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","punto_id") REFERENCES "public"."punto"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ficha" ADD CONSTRAINT "ficha_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ficha" ADD CONSTRAINT "ficha_lote_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","lote_id") REFERENCES "public"."lote"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ficha" ADD CONSTRAINT "ficha_lote_id_plan_id_punto_id_fkey" FOREIGN KEY ("punto_id","lote_id","plan_id") REFERENCES "public"."lote"("id","punto_id","plan_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orden" ADD CONSTRAINT "orden_cliente_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","cliente_id") REFERENCES "public"."cliente"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orden" ADD CONSTRAINT "orden_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orden" ADD CONSTRAINT "orden_ficha_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","ficha_id") REFERENCES "public"."ficha"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orden" ADD CONSTRAINT "orden_plan_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","plan_id") REFERENCES "public"."plan"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orden" ADD CONSTRAINT "orden_turno_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","turno_id") REFERENCES "public"."turno"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orden" ADD CONSTRAINT "orden_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "venta" ADD CONSTRAINT "venta_cliente_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","cliente_id") REFERENCES "public"."cliente"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "venta" ADD CONSTRAINT "venta_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "venta" ADD CONSTRAINT "venta_ficha_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","ficha_id") REFERENCES "public"."ficha"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "venta" ADD CONSTRAINT "venta_orden_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","orden_id") REFERENCES "public"."orden"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "venta" ADD CONSTRAINT "venta_plan_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","plan_id") REFERENCES "public"."plan"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "venta" ADD CONSTRAINT "venta_turno_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","turno_id") REFERENCES "public"."turno"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "venta" ADD CONSTRAINT "venta_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "anulacion" ADD CONSTRAINT "anulacion_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "anulacion" ADD CONSTRAINT "anulacion_turno_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","turno_id") REFERENCES "public"."turno"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "anulacion" ADD CONSTRAINT "anulacion_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "anulacion" ADD CONSTRAINT "anulacion_venta_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","venta_id") REFERENCES "public"."venta"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "entrega" ADD CONSTRAINT "entrega_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "entrega" ADD CONSTRAINT "entrega_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "entrega" ADD CONSTRAINT "entrega_venta_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","venta_id") REFERENCES "public"."venta"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "intento_venta" ADD CONSTRAINT "intento_venta_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "intento_venta" ADD CONSTRAINT "intento_venta_plan_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","plan_id") REFERENCES "public"."plan"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "intento_venta" ADD CONSTRAINT "intento_venta_turno_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","turno_id") REFERENCES "public"."turno"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "intento_venta" ADD CONSTRAINT "intento_venta_usuario_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","usuario_id") REFERENCES "public"."usuario"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "intento_venta" ADD CONSTRAINT "intento_venta_venta_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","venta_id") REFERENCES "public"."venta"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "stock_cierre" ADD CONSTRAINT "stock_cierre_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "stock_cierre" ADD CONSTRAINT "stock_cierre_plan_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","plan_id") REFERENCES "public"."plan"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "stock_cierre" ADD CONSTRAINT "stock_cierre_turno_id_comercio_id_fkey" FOREIGN KEY ("comercio_id","turno_id") REFERENCES "public"."turno"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "consumo" ADD CONSTRAINT "consumo_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "consumo" ADD CONSTRAINT "consumo_ficha_id_comercio_id_fkey" FOREIGN KEY ("ficha_id","comercio_id") REFERENCES "public"."ficha"("id","comercio_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "auditoria" ADD CONSTRAINT "auditoria_comercio_id_fkey" FOREIGN KEY ("comercio_id") REFERENCES "public"."comercio"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "punto_comercio_id_idx" ON "punto" USING btree ("comercio_id" uuid_ops) WHERE activo;--> statement-breakpoint
CREATE INDEX "pago_comercio_id_conciliado_en_idx" ON "pago" USING btree ("comercio_id" timestamptz_ops,"conciliado_en" uuid_ops) WHERE (metodo = 'manual'::text);--> statement-breakpoint
CREATE UNIQUE INDEX "pago_referencia" ON "pago" USING btree ("comercio_id" uuid_ops,"referencia" uuid_ops) WHERE (referencia IS NOT NULL);--> statement-breakpoint
CREATE UNIQUE INDEX "pago_un_exito" ON "pago" USING btree ("orden_id" uuid_ops) WHERE (estado = 'exitoso'::text);--> statement-breakpoint
CREATE INDEX "plan_comercio_id_orden_display_idx" ON "plan" USING btree ("comercio_id" int4_ops,"orden_display" int4_ops) WHERE activo;--> statement-breakpoint
CREATE INDEX "usuario_comercio_id_idx" ON "usuario" USING btree ("comercio_id" uuid_ops) WHERE activo;--> statement-breakpoint
CREATE UNIQUE INDEX "usuario_email_global" ON "usuario" USING btree ("email" text_ops) WHERE activo;--> statement-breakpoint
CREATE INDEX "turno_comercio_id_dia_operativo_idx" ON "turno" USING btree ("comercio_id" date_ops,"dia_operativo" uuid_ops);--> statement-breakpoint
CREATE UNIQUE INDEX "turno_uno_abierto_por_punto" ON "turno" USING btree ("punto_id" uuid_ops) WHERE (cerrado_en IS NULL);--> statement-breakpoint
CREATE INDEX "movimiento_caja_turno_id_idx" ON "movimiento_caja" USING btree ("turno_id" uuid_ops);--> statement-breakpoint
CREATE INDEX "lote_comercio_id_plan_id_idx" ON "lote" USING btree ("comercio_id" uuid_ops,"plan_id" uuid_ops);--> statement-breakpoint
CREATE INDEX "ficha_comercio_id_estado_idx" ON "ficha" USING btree ("comercio_id" uuid_ops,"estado" text_ops);--> statement-breakpoint
CREATE INDEX "ficha_lote_id_idx" ON "ficha" USING btree ("lote_id" uuid_ops);--> statement-breakpoint
CREATE INDEX "ficha_pool" ON "ficha" USING btree ("comercio_id" uuid_ops,"plan_id" uuid_ops) WHERE ((estado = 'disponible'::text) AND en_router);--> statement-breakpoint
CREATE INDEX "ficha_sin_cargar" ON "ficha" USING btree ("comercio_id" uuid_ops,"plan_id" uuid_ops) WHERE ((estado = 'disponible'::text) AND (NOT en_router));--> statement-breakpoint
CREATE INDEX "orden_turno_id_idx" ON "orden" USING btree ("turno_id" uuid_ops);--> statement-breakpoint
CREATE UNIQUE INDEX "orden_una_abierta" ON "orden" USING btree ("ficha_id" uuid_ops) WHERE (estado = 'abierta'::text);--> statement-breakpoint
CREATE INDEX "venta_comercio_id_fecha_local_idx" ON "venta" USING btree ("comercio_id" date_ops,"fecha_local" uuid_ops);--> statement-breakpoint
CREATE INDEX "venta_turno_id_idx" ON "venta" USING btree ("turno_id" uuid_ops);--> statement-breakpoint
CREATE INDEX "anulacion_turno_id_idx" ON "anulacion" USING btree ("turno_id" uuid_ops);--> statement-breakpoint
CREATE INDEX "intento_venta_comercio_id_fecha_local_idx" ON "intento_venta" USING btree ("comercio_id" date_ops,"fecha_local" date_ops);--> statement-breakpoint
CREATE INDEX "auditoria_comercio_id_ocurrido_en_idx" ON "auditoria" USING btree ("comercio_id" timestamptz_ops,"ocurrido_en" timestamptz_ops);--> statement-breakpoint
CREATE VIEW "public"."v_venta_vigente" AS (SELECT id, comercio_id, turno_id, usuario_id, ficha_id, orden_id, plan_id, cliente_id, metodo, monto_centimos, fecha_local, hora_local, comprobante_id, ocurrida_en FROM venta v WHERE NOT (EXISTS ( SELECT 1 FROM anulacion a WHERE a.venta_id = v.id)));--> statement-breakpoint
CREATE VIEW "public"."v_pool" AS (WITH disp AS ( SELECT ficha.comercio_id, ficha.plan_id, count(*) AS n FROM ficha WHERE ficha.estado = 'disponible'::text AND ficha.en_router GROUP BY ficha.comercio_id, ficha.plan_id ), pend AS ( SELECT ficha.comercio_id, ficha.plan_id, count(*) AS n FROM ficha WHERE ficha.estado = 'disponible'::text AND NOT ficha.en_router GROUP BY ficha.comercio_id, ficha.plan_id ) SELECT p.comercio_id, p.id AS plan_id, p.codigo, p.nombre, p.categoria, p.precio_centimos, COALESCE(d.n, 0::bigint)::integer AS disponibles, COALESCE(pe.n, 0::bigint)::integer AS sin_cargar, COALESCE(p.stock_minimo, ( SELECT min(pt.pool_minimo) AS min FROM punto pt WHERE pt.comercio_id = p.comercio_id AND pt.activo)) AS minimo FROM plan p LEFT JOIN disp d ON d.plan_id = p.id LEFT JOIN pend pe ON pe.plan_id = p.id WHERE p.activo);--> statement-breakpoint
CREATE VIEW "public"."v_stock_lote" AS (SELECT l.comercio_id, l.id AS lote_id, l.plan_id, p.nombre AS plan, l.cantidad, l.importacion_id, i.archivo, l.creado_en, l.anulado_en, count(*) FILTER (WHERE f.estado = 'disponible'::text AND f.en_router) AS disponibles, count(*) FILTER (WHERE f.estado = 'disponible'::text AND NOT f.en_router) AS sin_cargar, count(*) FILTER (WHERE f.estado = 'reservada'::text) AS reservadas, count(*) FILTER (WHERE f.estado = ANY (ARRAY['vendida'::text, 'activada'::text, 'agotada'::text, 'expirada'::text])) AS vendidas, count(*) FILTER (WHERE f.estado = 'anulada'::text) AS anuladas FROM lote l JOIN plan p ON p.id = l.plan_id LEFT JOIN importacion i ON i.id = l.importacion_id LEFT JOIN ficha f ON f.lote_id = l.id GROUP BY l.comercio_id, l.id, l.plan_id, p.nombre, l.cantidad, l.importacion_id, i.archivo, l.creado_en, l.anulado_en);--> statement-breakpoint
CREATE VIEW "public"."v_turno_actual" AS (SELECT t.comercio_id, t.id AS turno_id, t.punto_id, t.dia_operativo, u.nombre AS usuario, t.abierto_en, t.fondo_inicial, COALESCE(( SELECT sum(v.monto_centimos::integer) AS sum FROM venta v WHERE v.turno_id = t.id AND v.metodo = 'efectivo'::text), 0::bigint) AS efectivo_cobrado, COALESCE(( SELECT sum(v.monto_centimos::integer) AS sum FROM anulacion a JOIN venta v ON v.id = a.venta_id WHERE a.turno_id = t.id AND v.metodo = 'efectivo'::text), 0::bigint) AS efectivo_devuelto, COALESCE(( SELECT sum(m.monto_centimos::integer) AS sum FROM movimiento_caja m WHERE m.turno_id = t.id AND m.tipo <> 'fondo'::text), 0::bigint) AS movimientos, t.fondo_inicial::integer + COALESCE(( SELECT sum(v.monto_centimos::integer) AS sum FROM venta v WHERE v.turno_id = t.id AND v.metodo = 'efectivo'::text), 0::bigint) - COALESCE(( SELECT sum(v.monto_centimos::integer) AS sum FROM anulacion a JOIN venta v ON v.id = a.venta_id WHERE a.turno_id = t.id AND v.metodo = 'efectivo'::text), 0::bigint) + COALESCE(( SELECT sum(m.monto_centimos::integer) AS sum FROM movimiento_caja m WHERE m.turno_id = t.id AND m.tipo <> 'fondo'::text), 0::bigint) AS efectivo_esperado, ( SELECT count(*) AS count FROM v_venta_vigente v WHERE v.turno_id = t.id) AS fichas, ( SELECT count(*) AS count FROM pago pg JOIN orden o ON o.id = pg.orden_id WHERE o.turno_id = t.id AND pg.motivo_manual = 'pos_externo'::text AND pg.estado = 'exitoso'::text) AS pagos_pos FROM turno t JOIN usuario u ON u.id = t.usuario_id WHERE t.cerrado_en IS NULL);--> statement-breakpoint
CREATE VIEW "public"."v_pendiente_conciliar" AS (SELECT pg.comercio_id, pg.id AS pago_id, t.dia_operativo, u.nombre AS usuario, pg.medio, pg.referencia, pg.monto_centimos, pg.resuelto_en AS desde, o.numero FROM pago pg JOIN orden o ON o.id = pg.orden_id JOIN turno t ON t.id = o.turno_id JOIN usuario u ON u.id = o.usuario_id WHERE pg.metodo = 'manual'::text AND pg.estado = 'exitoso'::text AND pg.conciliado_en IS NULL);--> statement-breakpoint
CREATE VIEW "public"."v_alarma_sin_pago" AS (SELECT comercio_id, id AS venta_id FROM v_venta_vigente v WHERE NOT (EXISTS ( SELECT 1 FROM pago pg WHERE pg.orden_id = v.orden_id AND pg.estado = 'exitoso'::text)));--> statement-breakpoint
CREATE VIEW "public"."v_alarma_sin_venta" AS (SELECT pg.comercio_id, pg.id AS pago_id FROM pago pg JOIN orden o ON o.id = pg.orden_id WHERE pg.estado = 'exitoso'::text AND o.estado = 'pagada'::text AND NOT (EXISTS ( SELECT 1 FROM venta v WHERE v.orden_id = pg.orden_id)));--> statement-breakpoint
CREATE VIEW "public"."v_alarma_codigo_muerto" AS (SELECT comercio_id, id AS ficha_id, codigo FROM ficha f WHERE (estado = ANY (ARRAY['vendida'::text, 'activada'::text])) AND NOT en_router);--> statement-breakpoint
CREATE VIEW "public"."v_alarma_fuga_pool" AS (SELECT f.comercio_id, f.id AS ficha_id, f.codigo, c.uptime_seg FROM ficha f JOIN consumo c ON c.ficha_id = f.id WHERE (f.estado = ANY (ARRAY['disponible'::text, 'reservada'::text, 'anulada'::text])) AND (c.uptime_seg > 0 OR c.bytes_in > 0));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "punto" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "importacion" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "pago" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "incidencia" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "plan" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "usuario" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "turno" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "movimiento_caja" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "cliente" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "lote" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "ficha" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "orden" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "venta" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "anulacion" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "entrega" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "intento_venta" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "stock_cierre" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "consumo" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));--> statement-breakpoint
CREATE POLICY "aislamiento" ON "auditoria" AS PERMISSIVE FOR ALL TO public USING ((comercio_id = app_comercio())) WITH CHECK ((comercio_id = app_comercio()));
*/