--
-- PostgreSQL database dump
--

\restrict 6JudrwhNGe1xksW8ifgySeHIr9faUzjNq7Cn9rdwAj4ATAHNyZJJ3rsHEdTZkuT

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.accounts (
    id integer NOT NULL,
    name character varying(150) NOT NULL,
    account_type character varying(30) NOT NULL,
    is_active boolean,
    branch_id integer
);


ALTER TABLE public.accounts OWNER TO postgres;

--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.accounts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.accounts_id_seq OWNER TO postgres;

--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: advance_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.advance_orders (
    id integer NOT NULL,
    customer_id integer NOT NULL,
    product_id integer NOT NULL,
    color character varying(50),
    agreed_price integer NOT NULL,
    order_date timestamp without time zone,
    expected_delivery_date date,
    status character varying(20),
    notes character varying(255),
    unit_id integer,
    created_at timestamp without time zone,
    branch_id integer
);


ALTER TABLE public.advance_orders OWNER TO postgres;

--
-- Name: advance_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.advance_orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.advance_orders_id_seq OWNER TO postgres;

--
-- Name: advance_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.advance_orders_id_seq OWNED BY public.advance_orders.id;


--
-- Name: advance_payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.advance_payments (
    id integer NOT NULL,
    order_id integer NOT NULL,
    kind character varying(10),
    amount integer NOT NULL,
    payment_mode character varying(10),
    payment_date timestamp without time zone,
    voucher_id integer,
    note character varying(255)
);


ALTER TABLE public.advance_payments OWNER TO postgres;

--
-- Name: advance_payments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.advance_payments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.advance_payments_id_seq OWNER TO postgres;

--
-- Name: advance_payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.advance_payments_id_seq OWNED BY public.advance_payments.id;


--
-- Name: areas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.areas (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.areas OWNER TO postgres;

--
-- Name: areas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.areas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.areas_id_seq OWNER TO postgres;

--
-- Name: areas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.areas_id_seq OWNED BY public.areas.id;


--
-- Name: branches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.branches (
    id integer NOT NULL,
    company_id integer NOT NULL,
    name character varying(150) NOT NULL,
    address character varying(255),
    phone character varying(30),
    is_active boolean,
    created_at timestamp without time zone
);


ALTER TABLE public.branches OWNER TO postgres;

--
-- Name: branches_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.branches_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.branches_id_seq OWNER TO postgres;

--
-- Name: branches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.branches_id_seq OWNED BY public.branches.id;


--
-- Name: brands; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.brands (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.brands OWNER TO postgres;

--
-- Name: brands_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.brands_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.brands_id_seq OWNER TO postgres;

--
-- Name: brands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.brands_id_seq OWNED BY public.brands.id;


--
-- Name: change_requests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.change_requests (
    id integer NOT NULL,
    entity character varying(30) NOT NULL,
    action character varying(10) NOT NULL,
    target_id integer NOT NULL,
    summary character varying(255),
    payload text,
    status character varying(12),
    requested_by integer NOT NULL,
    requested_by_name character varying(100),
    requested_at timestamp without time zone,
    decided_by_name character varying(100),
    decided_at timestamp without time zone,
    decision_note character varying(255)
);


ALTER TABLE public.change_requests OWNER TO postgres;

--
-- Name: change_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.change_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.change_requests_id_seq OWNER TO postgres;

--
-- Name: change_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.change_requests_id_seq OWNED BY public.change_requests.id;


--
-- Name: companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.companies (
    id integer NOT NULL,
    name character varying(150) NOT NULL,
    address character varying(255),
    phone character varying(30),
    created_at timestamp without time zone
);


ALTER TABLE public.companies OWNER TO postgres;

--
-- Name: companies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.companies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.companies_id_seq OWNER TO postgres;

--
-- Name: companies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.companies_id_seq OWNED BY public.companies.id;


--
-- Name: parties; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.parties (
    id integer NOT NULL,
    name character varying(150) NOT NULL,
    party_type character varying(20) NOT NULL,
    phone character varying(30),
    address character varying(255),
    area_id integer,
    created_at timestamp without time zone
);


ALTER TABLE public.parties OWNER TO postgres;

--
-- Name: parties_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.parties_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.parties_id_seq OWNER TO postgres;

--
-- Name: parties_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.parties_id_seq OWNED BY public.parties.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id integer NOT NULL,
    brand_id integer NOT NULL,
    model_name character varying(150) NOT NULL,
    category character varying(50),
    unit_price integer,
    is_active boolean,
    created_at timestamp without time zone
);


ALTER TABLE public.products OWNER TO postgres;

--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.products_id_seq OWNER TO postgres;

--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE public.roles OWNER TO postgres;

--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_id_seq OWNER TO postgres;

--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: spare_parts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.spare_parts (
    id integer NOT NULL,
    name character varying(150) NOT NULL,
    unit character varying(20),
    stock_qty integer,
    purchase_price integer,
    sale_price integer,
    warehouse_id integer NOT NULL,
    created_at timestamp without time zone
);


ALTER TABLE public.spare_parts OWNER TO postgres;

--
-- Name: spare_parts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.spare_parts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.spare_parts_id_seq OWNER TO postgres;

--
-- Name: spare_parts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.spare_parts_id_seq OWNED BY public.spare_parts.id;


--
-- Name: supplier_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.supplier_orders (
    id integer NOT NULL,
    branch_id integer,
    supplier_id integer NOT NULL,
    product_id integer NOT NULL,
    qty integer NOT NULL,
    unit_price integer NOT NULL,
    order_date timestamp without time zone,
    expected_date date,
    status character varying(20),
    notes character varying(255),
    created_at timestamp without time zone
);


ALTER TABLE public.supplier_orders OWNER TO postgres;

--
-- Name: supplier_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.supplier_orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.supplier_orders_id_seq OWNER TO postgres;

--
-- Name: supplier_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.supplier_orders_id_seq OWNED BY public.supplier_orders.id;


--
-- Name: units; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.units (
    id integer NOT NULL,
    product_id integer NOT NULL,
    warehouse_id integer NOT NULL,
    chassis_no character varying(50) NOT NULL,
    engine_no character varying(50) NOT NULL,
    color character varying(50),
    year character varying(10),
    purchase_price integer NOT NULL,
    purchase_date timestamp without time zone,
    supplier_id integer,
    status character varying(20),
    sold_price integer,
    sold_date timestamp without time zone,
    customer_id integer,
    created_at timestamp without time zone,
    brta_status character varying DEFAULT 'not_started'::character varying,
    brta_reg_no character varying,
    brta_submission_date timestamp without time zone,
    brta_completion_date timestamp without time zone,
    brta_notes character varying,
    decoration_cost integer DEFAULT 0,
    registration_cost integer DEFAULT 0,
    supplier_order_id integer
);


ALTER TABLE public.units OWNER TO postgres;

--
-- Name: units_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.units_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.units_id_seq OWNER TO postgres;

--
-- Name: units_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.units_id_seq OWNED BY public.units.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(50) NOT NULL,
    password_hash character varying(255) NOT NULL,
    full_name character varying(100),
    role_id integer,
    is_active boolean,
    created_at timestamp without time zone,
    branch_id integer
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: voucher_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.voucher_entries (
    id integer NOT NULL,
    voucher_id integer NOT NULL,
    account_id integer NOT NULL,
    debit integer,
    credit integer,
    party_id integer
);


ALTER TABLE public.voucher_entries OWNER TO postgres;

--
-- Name: voucher_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.voucher_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.voucher_entries_id_seq OWNER TO postgres;

--
-- Name: voucher_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.voucher_entries_id_seq OWNED BY public.voucher_entries.id;


--
-- Name: vouchers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vouchers (
    id integer NOT NULL,
    voucher_type character varying(20) NOT NULL,
    voucher_date timestamp without time zone,
    reference character varying(150),
    narration character varying(255),
    created_at timestamp without time zone
);


ALTER TABLE public.vouchers OWNER TO postgres;

--
-- Name: vouchers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vouchers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vouchers_id_seq OWNER TO postgres;

--
-- Name: vouchers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vouchers_id_seq OWNED BY public.vouchers.id;


--
-- Name: warehouses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.warehouses (
    id integer NOT NULL,
    branch_id integer NOT NULL,
    name character varying(150) NOT NULL,
    location character varying(255),
    is_active boolean,
    created_at timestamp without time zone
);


ALTER TABLE public.warehouses OWNER TO postgres;

--
-- Name: warehouses_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.warehouses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.warehouses_id_seq OWNER TO postgres;

--
-- Name: warehouses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.warehouses_id_seq OWNED BY public.warehouses.id;


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: advance_orders id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_orders ALTER COLUMN id SET DEFAULT nextval('public.advance_orders_id_seq'::regclass);


--
-- Name: advance_payments id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_payments ALTER COLUMN id SET DEFAULT nextval('public.advance_payments_id_seq'::regclass);


--
-- Name: areas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.areas ALTER COLUMN id SET DEFAULT nextval('public.areas_id_seq'::regclass);


--
-- Name: branches id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches ALTER COLUMN id SET DEFAULT nextval('public.branches_id_seq'::regclass);


--
-- Name: brands id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.brands ALTER COLUMN id SET DEFAULT nextval('public.brands_id_seq'::regclass);


--
-- Name: change_requests id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.change_requests ALTER COLUMN id SET DEFAULT nextval('public.change_requests_id_seq'::regclass);


--
-- Name: companies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies ALTER COLUMN id SET DEFAULT nextval('public.companies_id_seq'::regclass);


--
-- Name: parties id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parties ALTER COLUMN id SET DEFAULT nextval('public.parties_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: spare_parts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spare_parts ALTER COLUMN id SET DEFAULT nextval('public.spare_parts_id_seq'::regclass);


--
-- Name: supplier_orders id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier_orders ALTER COLUMN id SET DEFAULT nextval('public.supplier_orders_id_seq'::regclass);


--
-- Name: units id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units ALTER COLUMN id SET DEFAULT nextval('public.units_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: voucher_entries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.voucher_entries ALTER COLUMN id SET DEFAULT nextval('public.voucher_entries_id_seq'::regclass);


--
-- Name: vouchers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vouchers ALTER COLUMN id SET DEFAULT nextval('public.vouchers_id_seq'::regclass);


--
-- Name: warehouses id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.warehouses ALTER COLUMN id SET DEFAULT nextval('public.warehouses_id_seq'::regclass);


--
-- Data for Name: accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.accounts (id, name, account_type, is_active, branch_id) FROM stdin;
1	Cash	cash	t	1
2	Sales Income	income	t	1
3	Accounts Receivable	receivable	t	1
4	Shop Rent	expense	t	1
5	bill	expense	t	1
6	Spare Parts Income	income	t	1
7	Inventory Purchase	expense	t	1
8	Accounts Payable	payable	t	1
9	Bank	bank	t	1
10	Customer Advances	advance	t	1
11	বিল	expense	t	1
12	Inventory Purchase	expense	t	3
13	Cash	cash	t	3
14	Supplier Advances	advance_paid	t	1
15	Decoration Income	income	t	1
\.


--
-- Data for Name: advance_orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.advance_orders (id, customer_id, product_id, color, agreed_price, order_date, expected_delivery_date, status, notes, unit_id, created_at, branch_id) FROM stdin;
1	2	1	green	285000	2026-10-04 17:07:48.499269	\N	delivered	10	18	2026-10-04 17:07:48.499289	1
2	2	3	\N	20	2026-10-08 07:18:50.575652	\N	cancelled	\N	\N	2026-10-08 07:18:50.575656	1
\.


--
-- Data for Name: advance_payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.advance_payments (id, order_id, kind, amount, payment_mode, payment_date, voucher_id, note) FROM stdin;
1	1	payment	100000	bank	2026-10-04 17:07:48.5303	35	প্রথম অগ্রিম
2	1	applied	100000	adjust	2026-10-04 17:08:51.085886	36	বিক্রয় ভাউচার #36-এ সমন্বয়
3	2	payment	10	cash	2026-10-08 07:18:50.584811	45	প্রথম অগ্রিম
4	2	refund	10	cash	2026-10-08 07:19:02.90176	46	\N
\.


--
-- Data for Name: areas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.areas (id, name) FROM stdin;
1	Pahartali
\.


--
-- Data for Name: branches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.branches (id, company_id, name, address, phone, is_active, created_at) FROM stdin;
1	1	Main Branch	Chattogram	01700000000	t	2026-09-02 16:31:30.269422
3	1	CNG অটো রিক্সা শোরুম	\N	\N	t	2026-10-06 03:25:01.256338
\.


--
-- Data for Name: brands; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.brands (id, name) FROM stdin;
1	Bajaj
2	bajaj
\.


--
-- Data for Name: change_requests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.change_requests (id, entity, action, target_id, summary, payload, status, requested_by, requested_by_name, requested_at, decided_by_name, decided_at, decision_note) FROM stdin;
1	warehouse	update	1	গোডাউন এডিট: Main Warehouse	{"branch_id": 2, "name": "sb corporation", "location": "Chattogram"}	rejected	2	rohim	2026-10-05 11:07:44.522181	admin	2026-10-05 11:08:34.131814	\N
\.


--
-- Data for Name: companies; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.companies (id, name, address, phone, created_at) FROM stdin;
1	Imam Motors	Chattogram	01700000000	2026-09-02 16:29:38.71115
\.


--
-- Data for Name: parties; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.parties (id, name, party_type, phone, address, area_id, created_at) FROM stdin;
1	Karim Motors	customer	01812345678	Pahartali, Chattogram	1	2026-09-03 04:16:24.927715
2	sobuj	customer	0101010	chotopool	\N	2026-09-05 07:22:56.839648
3	Rahim Traders	supplier	01912345678	\N	\N	2026-09-19 04:46:19.430553
4	Rahim Traders	supplier	01912345678	\N	\N	2026-09-19 04:53:27.201825
5	runner auto mobiles plc	supplier	\N	\N	\N	2026-10-08 05:25:09.099949
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (id, brand_id, model_name, category, unit_price, is_active, created_at) FROM stdin;
1	1	Pulsar 150	Motorcycle	285000	t	2026-09-03 04:14:32.02383
3	2	Bajaj CNG Auto Rickshaw 3w	236	\N	t	2026-10-06 15:30:29.048593
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles (id, name) FROM stdin;
1	Admin
2	staff
\.


--
-- Data for Name: spare_parts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spare_parts (id, name, unit, stock_qty, purchase_price, sale_price, warehouse_id, created_at) FROM stdin;
3	clutch plate	10	0	1200	1400	1	2026-09-18 13:55:01.91959
2	clutch plate	13	27	1200	1400	1	2026-09-18 13:53:47.815073
1	Brake Shoe	pcs	12	230	250	1	2026-09-15 05:18:46.285525
\.


--
-- Data for Name: supplier_orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.supplier_orders (id, branch_id, supplier_id, product_id, qty, unit_price, order_date, expected_date, status, notes, created_at) FROM stdin;
\.


--
-- Data for Name: units; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.units (id, product_id, warehouse_id, chassis_no, engine_no, color, year, purchase_price, purchase_date, supplier_id, status, sold_price, sold_date, customer_id, created_at, brta_status, brta_reg_no, brta_submission_date, brta_completion_date, brta_notes, decoration_cost, registration_cost, supplier_order_id) FROM stdin;
1	1	1	CH-2026-00123	EN-2026-00123	Red	2026	260000	2026-09-03 04:25:12.967631	\N	sold	285000	2026-09-03 04:28:08.6468	1	2026-09-03 04:25:12.967638	not_started	\N	\N	\N	\N	0	0	\N
2	1	1	CH-2026-00124	EN-2026-00124	Black	2026	260000	2026-09-03 04:34:05.318539	\N	sold	285000	2026-09-03 04:35:14.454606	1	2026-09-03 04:34:05.318546	not_started	\N	\N	\N	\N	0	0	\N
3	1	1	CH-2026-00125	EN-2026-00125	Blue	2026	260000	2026-09-03 04:40:39.794571	\N	sold	285000	2026-09-03 04:41:28.736101	1	2026-09-03 04:40:39.79458	not_started	\N	\N	\N	\N	0	0	\N
4	1	1	CH-2026-00126	EN-2026-00126	White	2026	260000	2026-09-03 11:24:55.888977	\N	sold	260000	2026-09-05 06:20:01.739898	1	2026-09-03 11:24:55.888983	not_started	\N	\N	\N	\N	0	0	\N
5	1	1	1212	2323	green	2026	210000	2026-09-03 12:05:05.521269	\N	sold	210000	2026-09-10 07:48:00.372193	2	2026-09-03 12:05:05.521273	not_started	\N	\N	\N	\N	0	0	\N
10	1	1	CH-TEST-019	EN-TEST-019	Silver	2026	260000	2026-09-15 07:14:24.224424	\N	sold	285000	2026-09-16 11:45:09.043856	1	2026-09-15 07:14:24.224449	not_started	\N	\N	\N	\N	0	0	\N
11	1	1	CH-TEST-020	EN-TEST-020	Silver	2026	260000	2026-09-16 11:59:02.469753	\N	sold	285000	2026-09-16 11:59:48.610957	1	2026-09-16 11:59:02.469759	not_started	\N	\N	\N	\N	0	0	\N
6	1	1	8776	099	green	2025	100000	2026-09-05 15:56:55.403325	\N	sold	100000	2026-09-17 05:54:05.191206	2	2026-09-05 15:56:55.403329	not_started	\N	\N	\N	\N	0	0	\N
7	1	1	23448	98877	blue	2026	1000000	2026-09-10 07:47:41.271386	\N	sold	1000000	2026-09-19 16:43:25.990216	1	2026-09-10 07:47:41.271393	not_started	\N	\N	\N	\N	0	0	\N
8	1	1	CH-TEST-001	EN-TEST-001	Silver	2026	260000	2026-09-15 07:03:41.515691	\N	sold	260000	2026-09-26 11:10:16.435543	2	2026-09-15 07:03:41.515695	not_started	\N	\N	\N	\N	0	0	\N
9	1	1	CH-TEST-009	EN-TEST-009	Silver	2026	260000	2026-09-15 07:08:51.48636	\N	sold	260000	2026-09-26 11:13:27.082391	1	2026-09-15 07:08:51.486369	not_started	\N	\N	\N	\N	0	0	\N
13	1	1	CH-SUP-002	EN-SUP-002	Black	2026	260000	2026-09-19 05:25:38.742037	4	sold	260000	2026-09-26 11:19:38.193777	1	2026-09-19 05:25:38.742044	not_started	\N	\N	\N	\N	0	0	\N
18	1	1	8000	9000	green	2001	300000	2026-10-03 06:25:53.266996	\N	sold	285000	2026-10-04 17:08:51.064731	2	2026-10-03 06:25:53.267001	not_started	\N	\N	\N	\N	0	0	\N
12	1	1	CH-SUP-001	EN-SUP-001	Black	2026	260000	2026-09-19 04:54:16.878873	4	sold	260000	2026-10-05 11:08:01.216798	2	2026-09-19 04:54:16.878876	not_started	\N	\N	\N	\N	0	0	\N
19	3	2	20001	2001	green	2026	625000	2026-10-06 15:31:25.033192	\N	in_stock	\N	\N	\N	2026-10-06 15:31:25.033203	not_started	\N	\N	\N	\N	0	0	\N
15	1	1	12345	1234	green	2026	5000000	2026-10-03 05:29:51.708677	\N	sold	5000000	2026-10-07 12:58:55.210604	2	2026-10-03 05:29:51.708708	not_started	\N	\N	\N	\N	0	0	\N
16	1	1	187676	676556	green	2026	20000	2026-10-03 06:21:02.123062	\N	sold	20000	2026-10-07 13:02:43.378316	2	2026-10-03 06:21:02.123072	not_started	\N	\N	\N	\N	0	0	\N
17	1	1	98767	8987	green	2000	200000	2026-10-03 06:21:02.210503	\N	sold	200000	2026-10-07 13:17:04.376434	2	2026-10-03 06:21:02.21051	not_started	\N	\N	\N	\N	0	0	\N
20	3	1	12120	12120	\N	\N	625000	2026-10-08 04:33:56.028797	4	sold	625000	2026-10-08 07:56:16.812187	2	2026-10-08 04:33:56.028805	not_started	\N	\N	\N	\N	0	0	\N
21	3	1	89889	098	\N	\N	625000	2026-10-08 07:57:22.156484	5	sold	625000	2026-10-08 08:02:11.674412	2	2026-10-08 07:57:22.156498	not_started	\N	\N	\N	\N	0	0	\N
22	3	1	191919	191919	\N	\N	500000	2026-10-10 07:46:51.489171	\N	sold	500000	2026-10-10 12:26:44.396694	2	2026-10-10 07:46:51.489186	not_started	\N	\N	\N	\N	0	0	\N
23	3	1	12345565	32	\N	\N	200000	2026-10-10 15:57:16.401364	\N	sold	200000	2026-10-10 15:58:58.17859	2	2026-10-10 15:57:16.401374	not_started	\N	\N	\N	\N	0	0	\N
24	3	1	63738	98283	\N	\N	200000	2026-10-10 16:00:19.984342	5	sold	200000	2026-10-10 16:00:39.160624	2	2026-10-10 16:00:19.984349	not_started	\N	\N	\N	\N	10000	0	\N
25	3	1	54345	5223	\N	\N	100000	2026-10-10 16:07:24.983978	5	sold	100000	2026-10-10 16:16:14.442704	2	2026-10-10 16:07:24.983987	not_started	\N	\N	\N	\N	0	0	\N
26	3	1	0884	4235	\N	\N	100000	2026-10-11 08:11:13.776348	\N	sold	100000	2026-10-11 08:17:11.063824	2	2026-10-11 08:11:13.776361	not_started	\N	\N	\N	\N	0	0	\N
27	3	1	934773	23	\N	\N	100000	2026-10-11 08:21:02.900876	\N	sold	100000	2026-10-11 10:11:33.988825	2	2026-10-11 08:21:02.900884	not_started	\N	\N	\N	\N	0	0	\N
28	3	1	123	097	\N	\N	10000	2026-10-11 15:19:49.845355	\N	sold	10000	2026-10-11 15:26:20.212324	2	2026-10-11 15:19:49.845365	not_started	\N	\N	\N	\N	0	0	\N
29	3	1	08782	09873	\N	\N	100000	2026-10-11 15:27:55.435702	\N	sold	100000	2026-10-11 15:37:09.314108	2	2026-10-11 15:27:55.435706	not_started	\N	\N	\N	\N	0	0	\N
30	3	1	123000	1356	\N	\N	10000	2026-10-11 15:54:37.682884	\N	sold	10000	2026-10-12 05:00:46.910614	2	2026-10-11 15:54:37.682889	not_started	\N	\N	\N	\N	0	0	\N
31	3	1	PS32A1BA4TFY01371	q	\N	\N	625000	2026-10-12 06:21:00.081352	\N	in_stock	\N	\N	\N	2026-10-12 06:21:00.081357	not_started	\N	\N	\N	\N	0	0	\N
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, password_hash, full_name, role_id, is_active, created_at, branch_id) FROM stdin;
1	admin	$2b$12$zvEIfRwIYBSlfCm2JkYEzul9BOJ4RHMh2aULgtD3NgPOnaRewt8zS	Imam	1	t	2026-09-02 15:23:09.70228	\N
2	rohim	$2b$12$d3Hg7UnvFiFPZZQQ/da0H.UQ2ACRne9HZdjsC65Ra7zNhME93NSRa	rohim	2	t	2026-10-05 11:05:16.014638	\N
\.


--
-- Data for Name: voucher_entries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.voucher_entries (id, voucher_id, account_id, debit, credit, party_id) FROM stdin;
1	1	1	285000	0	\N
2	1	2	0	285000	\N
3	2	3	285000	0	\N
4	2	2	0	285000	\N
5	3	4	15000	0	\N
6	3	1	0	15000	\N
7	4	1	100000	0	\N
8	4	3	0	100000	\N
9	5	3	260000	0	\N
10	5	2	0	260000	\N
11	6	1	50000	0	\N
12	6	3	0	50000	\N
13	7	1	5000	0	\N
14	7	3	0	5000	\N
15	8	1	5000	0	\N
16	8	3	0	5000	\N
17	9	1	210000	0	\N
18	9	2	0	210000	\N
19	10	5	122	0	\N
20	10	1	0	122	\N
21	11	1	1250	0	\N
22	11	6	0	1250	\N
23	13	3	285000	0	1
24	13	2	0	285000	\N
25	14	1	100000	0	\N
26	14	3	0	100000	1
27	15	1	100000	0	2
28	15	2	0	100000	\N
29	16	7	14400	0	\N
30	16	1	0	14400	\N
31	17	7	260000	0	\N
32	17	8	0	260000	4
33	18	7	260000	0	\N
34	18	8	0	260000	4
35	19	8	200000	0	4
36	19	1	0	200000	\N
37	20	7	230	0	\N
38	20	1	0	230	\N
39	21	7	18000	0	\N
40	21	1	0	18000	\N
41	22	7	230	0	\N
42	22	1	0	230	\N
43	23	3	1250	0	2
44	23	6	0	1250	\N
45	24	1	1000000	0	1
46	24	2	0	1000000	\N
47	25	3	260000	0	2
48	25	2	0	260000	\N
49	26	3	260000	0	1
50	26	2	0	260000	\N
51	27	1	260000	0	1
52	27	2	0	260000	\N
53	28	7	1000000	0	\N
54	28	1	0	1000000	\N
55	29	7	5000000	0	\N
56	29	1	0	5000000	\N
57	30	7	20000	0	\N
58	30	1	0	20000	\N
59	31	7	200000	0	\N
60	31	1	0	200000	\N
61	32	7	300000	0	\N
62	32	1	0	300000	\N
63	33	1	100000	0	\N
64	33	3	0	100000	1
65	34	1	100000	0	\N
66	34	3	0	100000	1
67	35	9	100000	0	2
68	35	10	0	100000	2
69	36	2	0	285000	\N
70	36	10	100000	0	2
71	36	1	100000	0	2
72	36	3	85000	0	2
73	37	11	100	0	\N
74	37	1	0	100	\N
75	38	1	260000	0	2
76	38	2	0	260000	\N
77	39	12	625000	0	\N
78	39	13	0	625000	\N
79	40	3	5000000	0	2
80	40	2	0	5000000	\N
81	41	1	10000	0	2
82	41	3	10000	0	2
83	41	2	0	20000	\N
84	42	1	200	0	2
85	42	3	199800	0	2
86	42	2	0	200000	\N
87	43	14	625000	0	3
88	43	9	0	625000	\N
89	44	7	625000	0	\N
90	44	8	0	625000	4
91	45	1	10	0	2
92	45	10	0	10	2
93	46	10	10	0	2
94	46	1	0	10	2
95	47	1	300000	0	2
96	47	3	325000	0	2
97	47	2	0	625000	\N
98	48	7	625000	0	\N
99	48	1	0	625000	5
100	49	1	100000	0	2
101	49	3	525000	0	2
102	49	2	0	625000	\N
103	50	7	500000	0	\N
104	50	1	0	500000	\N
105	51	3	500000	0	2
106	51	2	0	500000	\N
107	52	7	200000	0	\N
108	52	1	0	200000	\N
109	53	1	200000	0	2
110	53	2	0	200000	\N
111	54	7	200000	0	\N
112	54	1	0	200000	5
113	55	1	210000	0	2
114	55	2	0	200000	\N
115	55	15	0	10000	\N
116	56	7	100000	0	\N
117	56	1	0	100000	5
118	57	1	100000	0	2
119	57	2	0	100000	\N
120	58	7	100000	0	\N
121	58	1	0	100000	\N
122	59	1	100000	0	2
123	59	2	0	100000	\N
124	60	7	100000	0	\N
125	60	1	0	100000	\N
126	61	1	100000	0	2
127	61	2	0	100000	\N
128	62	7	10000	0	\N
129	62	1	0	10000	\N
130	63	1	10000	0	2
131	63	2	0	10000	\N
132	64	7	100000	0	\N
133	64	1	0	100000	\N
134	65	1	100000	0	2
135	65	2	0	100000	\N
136	66	7	10000	0	\N
137	66	1	0	10000	\N
138	67	1	10000	0	2
139	67	2	0	10000	\N
140	68	7	625000	0	\N
141	68	1	0	625000	\N
\.


--
-- Data for Name: vouchers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vouchers (id, voucher_type, voucher_date, reference, narration, created_at) FROM stdin;
1	sale	2026-09-03 04:35:14.47873	CH-2026-00124	Unit #2 (CH-2026-00124) বিক্রয়	2026-09-03 04:35:14.478735
2	sale	2026-09-03 04:41:28.748192	CH-2026-00125	Unit #3 (CH-2026-00125) বিক্রয়	2026-09-03 04:41:28.748199
3	payment	2026-09-03 06:25:48.189975	\N	সেপ্টেম্বর মাসের দোকান ভাড়া	2026-09-03 06:25:48.189979
4	receipt	2026-09-03 06:28:05.046947	\N	Karim Motors থেকে আংশিক আদায়	2026-09-03 06:28:05.046971
5	sale	2026-09-05 06:20:01.760448	CH-2026-00126	Unit #4 (CH-2026-00126) বিক্রয়	2026-09-05 06:20:01.760456
6	receipt	2026-09-05 15:41:54.847089	\N	Karim Motors থেকে বাকি আদায়	2026-09-05 15:41:54.847094
7	receipt	2026-09-05 15:50:08.006342	\N	Karim Motors থেকে বাকি আদায়	2026-09-05 15:50:08.006349
8	receipt	2026-09-05 15:56:08.049631	\N	Karim Motors থেকে বাকি আদায়	2026-09-05 15:56:08.049634
9	sale	2026-09-10 07:48:00.386802	1212	Unit #5 (1212) বিক্রয়	2026-09-10 07:48:00.386807
10	payment	2026-09-11 12:43:21.169757	\N	bill	2026-09-11 12:43:21.169765
11	sale	2026-09-15 05:56:51.659157	part-1	স্পেয়ার পার্টস বিক্রয়: Brake Shoe x5	2026-09-15 05:56:51.659163
12	sale	2026-09-16 11:45:09.058144	CH-TEST-019	Unit #10 (CH-TEST-019) বিক্রয়	2026-09-16 11:45:09.058149
13	sale	2026-09-16 11:59:48.627036	CH-TEST-020	Unit #11 (CH-TEST-020) বিক্রয়	2026-09-16 11:59:48.627044
14	receipt	2026-09-16 12:03:53.359687	\N	টেস্ট আদায়	2026-09-16 12:03:53.359693
15	sale	2026-09-17 05:54:05.198035	8776	Unit #6 (8776) বিক্রয়	2026-09-17 05:54:05.198045
16	purchase	2026-09-18 13:54:28.178487	part-2	স্পেয়ার পার্টস ক্রয়: clutch plate x12	2026-09-18 13:54:28.178495
17	purchase	2026-09-19 04:54:16.902767	CH-SUP-001	Unit #12 (CH-SUP-001) ক্রয়	2026-09-19 04:54:16.902773
18	purchase	2026-09-19 05:25:38.757897	CH-SUP-002	Unit #13 (CH-SUP-002) ক্রয়	2026-09-19 05:25:38.757903
19	payment	2026-09-19 05:27:58.456981	\N	Rahim Traders-কে পরিশোধ	2026-09-19 05:27:58.456988
20	purchase	2026-09-19 07:00:24.959327	part-1	স্পেয়ার পার্টস ক্রয়: Brake Shoe x1	2026-09-19 07:00:24.959335
21	purchase	2026-09-19 07:01:48.268123	part-2	স্পেয়ার পার্টস ক্রয়: clutch plate x15	2026-09-19 07:01:48.268127
22	purchase	2026-09-19 07:02:11.1762	part-1	স্পেয়ার পার্টস ক্রয়: Brake Shoe x1	2026-09-19 07:02:11.176204
23	sale	2026-09-19 07:04:31.646475	part-1	স্পেয়ার পার্টস বিক্রয়: Brake Shoe x5	2026-09-19 07:04:31.646481
24	sale	2026-09-19 16:43:26.014036	23448	Unit #7 (23448) বিক্রয়	2026-09-19 16:43:26.014046
25	sale	2026-09-26 11:10:16.483657	CH-TEST-001	Unit #8 (CH-TEST-001) বিক্রয়	2026-09-26 11:10:16.483666
26	sale	2026-09-26 11:13:27.085559	CH-TEST-009	Unit #9 (CH-TEST-009) বিক্রয়	2026-09-26 11:13:27.085565
27	sale	2026-09-26 11:19:38.202514	CH-SUP-002	Unit #13 (CH-SUP-002) বিক্রয়	2026-09-26 11:19:38.20252
28	purchase	2026-09-26 12:47:38.434988	039389	Unit #14 (039389) ক্রয়	2026-09-26 12:47:38.434992
29	purchase	2026-10-03 05:29:51.742315	12345	Unit #15 (12345) ক্রয়	2026-10-03 05:29:51.74232
30	purchase	2026-10-03 06:21:02.146144	187676	Unit #16 (187676) ক্রয়	2026-10-03 06:21:02.146151
31	purchase	2026-10-03 06:21:02.219061	98767	Unit #17 (98767) ক্রয়	2026-10-03 06:21:02.219067
32	purchase	2026-10-03 06:25:53.299407	8000	Unit #18 (8000) ক্রয়	2026-10-03 06:25:53.299411
33	receipt	2026-10-03 06:55:22.986568	\N	Karim Motors থেকে বাকি আদায়	2026-10-03 06:55:22.986597
34	receipt	2026-10-03 15:45:17.13607	\N	Karim Motors থেকে বাকি আদায়	2026-10-03 15:45:17.136077
35	advance	2026-10-04 17:07:48.525816	adv-1	প্রথম অগ্রিম	2026-10-04 17:07:48.525821
36	sale	2026-10-04 17:08:51.077084	8000	Unit #18 (8000) বিক্রয় — অগ্রিম অর্ডার #1	2026-10-04 17:08:51.077088
37	payment	2026-10-04 17:32:58.233459	\N	বিল	2026-10-04 17:32:58.233462
38	sale	2026-10-05 11:08:01.225538	CH-SUP-001	Unit #12 (CH-SUP-001) বিক্রয়	2026-10-05 11:08:01.225543
39	purchase	2026-10-06 15:31:25.075048	20001	Unit #19 (20001) ক্রয়	2026-10-06 15:31:25.075055
40	sale	2026-10-07 12:58:55.241685	12345	Unit #15 (12345) বিক্রয়	2026-10-07 12:58:55.24169
41	sale	2026-10-07 13:02:43.401691	187676	Unit #16 (187676) বিক্রয়	2026-10-07 13:02:43.401719
42	sale	2026-10-07 13:17:04.381439	98767	Unit #17 (98767) বিক্রয়	2026-10-07 13:17:04.381446
43	advance	2026-10-08 04:32:23.422348	sadv-3	1	2026-10-08 04:32:23.422353
44	purchase	2026-10-08 04:33:56.043438	12120	Unit #20 (12120) ক্রয়	2026-10-08 04:33:56.043444
45	advance	2026-10-08 07:18:50.581442	adv-2	প্রথম অগ্রিম	2026-10-08 07:18:50.581446
46	advance	2026-10-08 07:19:02.893075	adv-2	অগ্রিম অর্ডার #2 বাতিল	2026-10-08 07:19:02.893082
47	sale	2026-10-08 07:56:16.821439	12120	Unit #20 (12120) বিক্রয়	2026-10-08 07:56:16.821446
48	purchase	2026-10-08 07:57:22.170567	89889	Unit #21 (89889) ক্রয়	2026-10-08 07:57:22.17058
49	sale	2026-10-08 08:02:11.678456	89889	Unit #21 (89889) বিক্রয়	2026-10-08 08:02:11.678494
50	purchase	2026-10-10 07:46:51.511372	191919	Unit #22 (191919) ক্রয়	2026-10-10 07:46:51.51138
51	sale	2026-10-10 12:26:44.408692	191919	Unit #22 (191919) বিক্রয়	2026-10-10 12:26:44.408696
52	purchase	2026-10-10 15:57:16.417979	12345565	Unit #23 (12345565) ক্রয়	2026-10-10 15:57:16.417985
53	sale	2026-10-10 15:58:58.186279	12345565	Unit #23 (12345565) বিক্রয়	2026-10-10 15:58:58.186284
54	purchase	2026-10-10 16:00:19.990534	63738	Unit #24 (63738) ক্রয়	2026-10-10 16:00:19.99054
55	sale	2026-10-10 16:00:39.164768	63738	Unit #24 (63738) বিক্রয়	2026-10-10 16:00:39.164774
56	purchase	2026-10-10 16:07:24.997828	54345	Unit #25 (54345) ক্রয়	2026-10-10 16:07:24.997835
57	sale	2026-10-10 16:16:14.447241	54345	Unit #25 (54345) বিক্রয়	2026-10-10 16:16:14.44725
58	purchase	2026-10-11 08:11:13.795315	0884	Unit #26 (0884) ক্রয়	2026-10-11 08:11:13.795325
59	sale	2026-10-11 08:17:11.073749	0884	Unit #26 (0884) বিক্রয়	2026-10-11 08:17:11.073755
60	purchase	2026-10-11 08:21:02.908372	934773	Unit #27 (934773) ক্রয়	2026-10-11 08:21:02.908382
61	sale	2026-10-11 10:11:33.994205	934773	Unit #27 (934773) বিক্রয়	2026-10-11 10:11:33.994214
62	purchase	2026-10-11 15:19:49.857973	123	Unit #28 (123) ক্রয়	2026-10-11 15:19:49.857977
63	sale	2026-10-11 15:26:20.220236	123	Unit #28 (123) বিক্রয়	2026-10-11 15:26:20.220241
64	purchase	2026-10-11 15:27:55.441086	08782	Unit #29 (08782) ক্রয়	2026-10-11 15:27:55.441091
65	sale	2026-10-11 15:37:09.317216	08782	Unit #29 (08782) বিক্রয়	2026-10-11 15:37:09.317223
66	purchase	2026-10-11 15:54:37.69075	123000	Unit #30 (123000) ক্রয়	2026-10-11 15:54:37.690754
67	sale	2026-10-12 05:00:46.924044	123000	Unit #30 (123000) বিক্রয়	2026-10-12 05:00:46.924052
68	purchase	2026-10-12 06:21:00.091571	PS32A1BA4TFY01371	Unit #31 (PS32A1BA4TFY01371) ক্রয়	2026-10-12 06:21:00.091575
\.


--
-- Data for Name: warehouses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.warehouses (id, branch_id, name, location, is_active, created_at) FROM stdin;
2	3	CNG শোরুম গোডাউন	\N	t	2026-10-06 03:25:01.256338
3	3	Imam	chotopool	t	2026-10-06 10:48:37.286799
1	1	Main Warehouse	Chattogram	t	2026-09-02 16:46:30.817858
\.


--
-- Name: accounts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.accounts_id_seq', 15, true);


--
-- Name: advance_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.advance_orders_id_seq', 2, true);


--
-- Name: advance_payments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.advance_payments_id_seq', 4, true);


--
-- Name: areas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.areas_id_seq', 1, true);


--
-- Name: branches_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.branches_id_seq', 3, true);


--
-- Name: brands_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.brands_id_seq', 2, true);


--
-- Name: change_requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.change_requests_id_seq', 1, true);


--
-- Name: companies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.companies_id_seq', 1, true);


--
-- Name: parties_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.parties_id_seq', 5, true);


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 3, true);


--
-- Name: roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.roles_id_seq', 2, true);


--
-- Name: spare_parts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.spare_parts_id_seq', 3, true);


--
-- Name: supplier_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.supplier_orders_id_seq', 1, false);


--
-- Name: units_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.units_id_seq', 31, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 2, true);


--
-- Name: voucher_entries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.voucher_entries_id_seq', 141, true);


--
-- Name: vouchers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vouchers_id_seq', 68, true);


--
-- Name: warehouses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.warehouses_id_seq', 3, true);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: advance_orders advance_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_orders
    ADD CONSTRAINT advance_orders_pkey PRIMARY KEY (id);


--
-- Name: advance_payments advance_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_payments
    ADD CONSTRAINT advance_payments_pkey PRIMARY KEY (id);


--
-- Name: areas areas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.areas
    ADD CONSTRAINT areas_pkey PRIMARY KEY (id);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: brands brands_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.brands
    ADD CONSTRAINT brands_name_key UNIQUE (name);


--
-- Name: brands brands_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.brands
    ADD CONSTRAINT brands_pkey PRIMARY KEY (id);


--
-- Name: change_requests change_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.change_requests
    ADD CONSTRAINT change_requests_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: parties parties_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parties
    ADD CONSTRAINT parties_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: spare_parts spare_parts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spare_parts
    ADD CONSTRAINT spare_parts_pkey PRIMARY KEY (id);


--
-- Name: supplier_orders supplier_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier_orders
    ADD CONSTRAINT supplier_orders_pkey PRIMARY KEY (id);


--
-- Name: units units_chassis_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_chassis_no_key UNIQUE (chassis_no);


--
-- Name: units units_engine_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_engine_no_key UNIQUE (engine_no);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: voucher_entries voucher_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.voucher_entries
    ADD CONSTRAINT voucher_entries_pkey PRIMARY KEY (id);


--
-- Name: vouchers vouchers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vouchers
    ADD CONSTRAINT vouchers_pkey PRIMARY KEY (id);


--
-- Name: warehouses warehouses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: advance_orders advance_orders_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_orders
    ADD CONSTRAINT advance_orders_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: advance_orders advance_orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_orders
    ADD CONSTRAINT advance_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.parties(id);


--
-- Name: advance_orders advance_orders_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_orders
    ADD CONSTRAINT advance_orders_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: advance_orders advance_orders_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_orders
    ADD CONSTRAINT advance_orders_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id);


--
-- Name: advance_payments advance_payments_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_payments
    ADD CONSTRAINT advance_payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.advance_orders(id);


--
-- Name: advance_payments advance_payments_voucher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.advance_payments
    ADD CONSTRAINT advance_payments_voucher_id_fkey FOREIGN KEY (voucher_id) REFERENCES public.vouchers(id);


--
-- Name: branches branches_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: parties parties_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parties
    ADD CONSTRAINT parties_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.areas(id);


--
-- Name: products products_brand_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: spare_parts spare_parts_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spare_parts
    ADD CONSTRAINT spare_parts_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id);


--
-- Name: supplier_orders supplier_orders_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier_orders
    ADD CONSTRAINT supplier_orders_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: supplier_orders supplier_orders_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier_orders
    ADD CONSTRAINT supplier_orders_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: supplier_orders supplier_orders_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier_orders
    ADD CONSTRAINT supplier_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.parties(id);


--
-- Name: units units_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.parties(id);


--
-- Name: units units_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: units units_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.parties(id);


--
-- Name: units units_supplier_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_supplier_order_id_fkey FOREIGN KEY (supplier_order_id) REFERENCES public.supplier_orders(id);


--
-- Name: units units_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id);


--
-- Name: users users_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: voucher_entries voucher_entries_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.voucher_entries
    ADD CONSTRAINT voucher_entries_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: voucher_entries voucher_entries_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.voucher_entries
    ADD CONSTRAINT voucher_entries_party_id_fkey FOREIGN KEY (party_id) REFERENCES public.parties(id);


--
-- Name: voucher_entries voucher_entries_voucher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.voucher_entries
    ADD CONSTRAINT voucher_entries_voucher_id_fkey FOREIGN KEY (voucher_id) REFERENCES public.vouchers(id);


--
-- Name: warehouses warehouses_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- PostgreSQL database dump complete
--

\unrestrict 6JudrwhNGe1xksW8ifgySeHIr9faUzjNq7Cn9rdwAj4ATAHNyZJJ3rsHEdTZkuT

