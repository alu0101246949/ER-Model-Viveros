DROP DATABASE IF EXISTS viveros;
DROP TABLE IF EXISTS purchase, client, work, employee, inventory, exhibitor, warehouse, exterior, vivarium_zone, vivarium, decoration, gardening, plant, product CASCADE;

CREATE DATABASE viveros;

-----------------------------TABLES-----------------------------

CREATE TABLE product (
    id_product SERIAL PRIMARY KEY,
    prod_name VARCHAR(50) UNIQUE NOT NULL,
    price DOUBLE PRECISION CHECK (price > 0) NOT NULL,
    stock_units INT CHECK (stock_units >= 0) NOT NULL
);

CREATE TABLE plant (
    id_plant SERIAL PRIMARY KEY,
    id_product INT NOT NULL,
    FOREIGN KEY (id_product) REFERENCES product(id_product) ON DELETE CASCADE
);

CREATE TABLE gardening (
    id_gardening SERIAL PRIMARY KEY,
    id_product INT NOT NULL,
    FOREIGN KEY (id_product) REFERENCES product(id_product) ON DELETE CASCADE
);

CREATE TABLE decoration (
    id_decoration SERIAL PRIMARY KEY,
    id_product INT NOT NULL,
    FOREIGN KEY (id_product) REFERENCES product(id_product) ON DELETE CASCADE
);

CREATE TABLE vivarium (
    id_vivarium SERIAL PRIMARY KEY,
    viv_name VARCHAR(50) NOT NULL,
    latitude DOUBLE PRECISION CHECK (latitude BETWEEN -90 AND 90) NOT NULL,
    longitude DOUBLE PRECISION CHECK (longitude BETWEEN -180 AND 180) NOT NULL, 
    stock_units INT CHECK (stock_units >= 0) NOT NULL
);

CREATE TABLE vivarium_zone (
    id_zone SERIAL PRIMARY KEY,
    id_vivarium INT NOT NULL,
    zone_name VARCHAR(50) NOT NULL,
    latitude DOUBLE PRECISION CHECK (latitude BETWEEN -90 AND 90) NOT NULL,
    longitude DOUBLE PRECISION CHECK (longitude BETWEEN -180 AND 180) NOT NULL, 
    stock_units INT CHECK (stock_units >= 0) NOT NULL,
    productivity INT CHECK (productivity >= 0) NOT NULL,
    FOREIGN KEY (id_vivarium) REFERENCES vivarium(id_vivarium) ON DELETE CASCADE
);

CREATE TABLE exterior (
    id_exterior SERIAL PRIMARY KEY,
    id_zone INT NOT NULL,
    FOREIGN KEY (id_zone) REFERENCES vivarium_zone(id_zone) ON DELETE CASCADE
);

CREATE TABLE warehouse (
    id_warehouse SERIAL PRIMARY KEY,
    id_zone INT NOT NULL,
    FOREIGN KEY (id_zone) REFERENCES vivarium_zone(id_zone) ON DELETE CASCADE
);

CREATE TABLE exhibitor (
    id_exhibitor SERIAL PRIMARY KEY,
    id_zone INT NOT NULL,
    FOREIGN KEY (id_zone) REFERENCES vivarium_zone(id_zone) ON DELETE CASCADE
);

CREATE TABLE inventory (
    id_product INT NOT NULL,
    id_zone INT NOT NULL,
    stock_units INT CHECK (stock_units >= 0) NOT NULL,
    FOREIGN KEY (id_product) REFERENCES product(id_product) ON DELETE CASCADE,
    FOREIGN KEY (id_zone) REFERENCES vivarium_zone(id_zone) ON DELETE CASCADE
);

CREATE TABLE employee (
    id_employee SERIAL PRIMARY KEY,
    empl_name VARCHAR(50) NOT NULL,
    empl_surname VARCHAR(50) NOT NULL,
    productivity INT CHECK (productivity >= 0) NOT NULL
);

CREATE TABLE work (
    id_employee INT NOT NULL,
    id_zone INT NOT NULL,
    init_date DATE NOT NULL,
    end_date DATE NOT NULL,
    hours_worked DOUBLE PRECISION CHECK (hours_worked >= 0) NOT NULL,
    FOREIGN KEY (id_employee) REFERENCES employee(id_employee) ON DELETE CASCADE,
    FOREIGN KEY (id_zone) REFERENCES vivarium_zone(id_zone) ON DELETE SET NULL
);

CREATE TABLE client (
    id_client SERIAL PRIMARY KEY,
    entry_date DATE NOT NULL,
    bonus INT CHECK (bonus >= 0) NOT NULL
);

CREATE TABLE purchase (
    id_purchase SERIAL PRIMARY KEY,
    id_product INT NOT NULL,
    id_client INT,
    id_employee INT NOT NULL,
    id_zone INT NOT NULL,
    units INT CHECK (units >= 0) NOT NULL,
    FOREIGN KEY (id_product) REFERENCES product(id_product) ON DELETE CASCADE,
    FOREIGN KEY (id_client) REFERENCES client(id_client) ON DELETE SET NULL,
    FOREIGN KEY (id_employee) REFERENCES employee(id_employee) ON DELETE CASCADE,
    FOREIGN KEY (id_zone) REFERENCES vivarium_zone(id_zone) ON DELETE CASCADE
);

-----------------------------TRIGGERS-----------------------------

-- TRIGGER
CREATE OR REPLACE FUNCTION update_zone_stock_from_inventory()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE vivarium_zone
    SET stock_units = (
        SELECT SUM(stock_units)
        FROM inventory
        WHERE id_zone = NEW.id_zone
    )
    WHERE id_zone = NEW.id_zone;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_zone_stock_from_inventory
AFTER INSERT OR UPDATE ON inventory
FOR EACH ROW
EXECUTE FUNCTION update_zone_stock_from_inventory();

-- TRIGGER
CREATE OR REPLACE FUNCTION update_employee_productivity()
RETURNS TRIGGER AS $$
DECLARE
    total_hours DOUBLE PRECISION;
BEGIN
    SELECT SUM(hours_worked) INTO total_hours
    FROM work
    WHERE id_employee = NEW.id_employee;

    UPDATE employee 
    SET productivity = total_hours / 8
    WHERE id_employee = NEW.id_employee;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_productivity
AFTER INSERT OR UPDATE ON work
FOR EACH ROW
EXECUTE FUNCTION update_employee_productivity();

-- TRIGGER
CREATE OR REPLACE FUNCTION update_zone_productivity()
RETURNS TRIGGER AS $$
DECLARE
    affected_zone_id INT;
BEGIN

    SELECT id_zone INTO affected_zone_id FROM work WHERE id_employee = NEW.id_employee;
    
    UPDATE vivarium_zone
    SET productivity = (
        SELECT SUM(e.productivity)
        FROM employee e
        INNER JOIN work w ON w.id_employee = e.id_employee
        WHERE w.id_zone = affected_zone_id
    )
    WHERE id_zone = affected_zone_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_update_zone_productivity_work
AFTER INSERT OR UPDATE OR DELETE ON employee
FOR EACH ROW
EXECUTE FUNCTION update_zone_productivity();

-- TRIGGER
CREATE OR REPLACE FUNCTION update_client_bonus()
RETURNS TRIGGER AS $$
DECLARE
    total_purchases INT;
BEGIN

    SELECT COUNT(*) INTO total_purchases FROM purchase WHERE id_client = NEW.id_client;

    IF total_purchases BETWEEN 1 AND 5 THEN
        UPDATE client SET bonus = 5 WHERE id_client = NEW.id_client;
    ELSIF total_purchases BETWEEN 6 AND 10 THEN
        UPDATE client SET bonus = 10 WHERE id_client = NEW.id_client;
    ELSE
        UPDATE client SET bonus = 15 WHERE id_client = NEW.id_client;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_bonus
AFTER INSERT ON purchase
FOR EACH ROW
EXECUTE FUNCTION update_client_bonus();

-- TRIGGER
CREATE OR REPLACE FUNCTION check_stock_consistency()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.stock_units + COALESCE((SELECT SUM(stock_units) FROM inventory WHERE id_product = NEW.id_product), 0)) 
        > (SELECT stock_units FROM product WHERE id_product = NEW.id_product) THEN
        RAISE EXCEPTION 'La suma del stock en todas las zonas excede el stock total del producto';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_stock_consistency
BEFORE INSERT ON inventory
FOR EACH ROW
EXECUTE FUNCTION check_stock_consistency();

-- TRIGGER
CREATE OR REPLACE FUNCTION verify_product_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.units > (
        SELECT stock_units 
        FROM inventory 
        WHERE id_product = NEW.id_product AND id_zone = NEW.id_zone
    ) THEN
        RAISE EXCEPTION 'No hay suficientes unidades del producto en esta zona';
    END IF;

    UPDATE inventory
    SET stock_units = stock_units - NEW.units
    WHERE id_zone = NEW.id_zone;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_verify_stock
BEFORE INSERT ON purchase
FOR EACH ROW 
EXECUTE FUNCTION verify_product_stock();

-----------------------------INSERTS-----------------------------

-- Insertando datos en la tabla product
INSERT INTO product (prod_name, price, stock_units) VALUES
('Rosa', 5.0, 100),
('Tulipán', 3.5, 50),
('Maceta', 10.0, 30),
('Pala', 12.5, 25),
('Lámpara de Jardín', 20.0, 15),
('Orquídea', 7.5, 80),
('Varillas', 7.0, 20),
('Regadera', 8.0, 40),
('Guantes', 5.5, 50),
('Fertilizante', 15.0, 60),
('Cactus', 10.0, 70),
('Helecho', 6.0, 90),
('Tijeras de podar', 18.0, 35),
('Sustrato', 14.0, 45),
('Farol Solar', 25.0, 40);

-- Insertando datos en las tablas plant, gardening y decoration
INSERT INTO plant (id_product) VALUES (1), (2), (6), (11), (12);
INSERT INTO gardening (id_product) VALUES (3), (4), (7), (8), (9);
INSERT INTO decoration (id_product) VALUES (5), (10), (13), (14), (15);

-- Insertando datos en la tabla vivarium
INSERT INTO vivarium (viv_name, latitude, longitude, stock_units) VALUES
('Vivarium Central', 40.730610, -73.935242, 500),
('Vivarium Norte', 52.520008, 13.404954, 450),
('Vivarium Sur', 34.052235, -118.243683, 650),
('Vivarium Este', 51.509865, -0.118092, 400),
('Vivarium Oeste', 48.864716, 2.349014, 550);

INSERT INTO vivarium_zone (id_vivarium, zone_name, latitude, longitude, stock_units, productivity) VALUES
(1, 'Zona A', 40.730000, -73.930000, 100, 5),
(1, 'Zona B', 40.731000, -73.931000, 150, 6),
(2, 'Zona C', 52.525000, 13.405000, 50, 4),
(2, 'Zona D', 52.526000, 13.406000, 75, 7),
(3, 'Zona E', 34.055000, -118.240000, 325, 8),
(3, 'Zona F', 34.056000, -118.241000, 80, 6),
(4, 'Zona G', 51.508865, -0.117092, 60, 5),
(4, 'Zona H', 51.507865, -0.116092, 90, 7),
(5, 'Zona I', 48.863716, 2.348014, 100, 6),
(5, 'Zona J', 48.865716, 2.350014, 150, 8),
(1, 'Zona K', 40.732000, -73.932000, 110, 7),
(2, 'Zona L', 52.524000, 13.404000, 70, 6),
(3, 'Zona M', 34.054000, -118.239000, 120, 5),
(4, 'Zona N', 51.506865, -0.115092, 130, 8),
(5, 'Zona O', 48.862716, 2.347014, 90, 7);

-- Insertando datos en las tablas exterior, warehouse y exhibitor
INSERT INTO exterior (id_zone) VALUES (1), (2), (6), (7), (11);
INSERT INTO warehouse (id_zone) VALUES (3), (4), (8), (9), (12);
INSERT INTO exhibitor (id_zone) VALUES (5), (10), (13), (14), (15);

-- Insertando datos en la tabla inventory
INSERT INTO inventory (id_product, id_zone, stock_units) VALUES
(1, 1, 50),
(2, 1, 25),
(3, 2, 15),
(4, 3, 10),
(5, 4, 5);

-- Insertando datos en la tabla employee
INSERT INTO employee (empl_name, empl_surname, productivity) VALUES
('Ana', 'Ramirez', 7),
('Luis', 'Gonzalez', 6),
('Sofia', 'Martinez', 8),
('Carlos', 'Fernandez', 5),
('Maria', 'Perez', 7);

-- Insertando datos en la tabla work
INSERT INTO work (id_employee, id_zone, init_date, end_date, hours_worked) VALUES
(1, 1, '2023-01-01', '2023-01-02', 8),
(2, 2, '2023-01-03', '2023-01-04', 7),
(3, 3, '2023-01-05', '2023-01-06', 6),
(4, 4, '2023-01-07', '2023-01-08', 5),
(5, 5, '2023-01-09', '2023-01-10', 7);

-- Insertando datos en la tabla client
INSERT INTO client (entry_date, bonus) VALUES
('2023-01-01', 10),
('2023-01-05', 15),
('2023-01-10', 20),
('2023-01-15', 5),
('2023-01-20', 10);

-- Insertando datos en la tabla purchase
INSERT INTO purchase (id_product, id_client, id_employee, id_zone, units) VALUES
(1, 1, 1, 1, 5),
(2, 2, 2, 2, 3),
(3, 3, 3, 3, 2),
(4, 4, 4, 4, 4),
(5, 5, 5, 5, 1);
