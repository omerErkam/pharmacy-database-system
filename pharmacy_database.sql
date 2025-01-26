-- 1. Person Table
CREATE TABLE Person (
    ID NUMBER PRIMARY KEY,
    Name VARCHAR2(100) NOT NULL
);

-- 2. Doctor Table (Inherits from Person)
CREATE TABLE Doctor (
    ID NUMBER PRIMARY KEY,
    Speciality VARCHAR2(100) NOT NULL,
    Hospital_Name VARCHAR2(100) NOT NULL,
    FOREIGN KEY (ID) REFERENCES Person(ID)
);

-- 3. Customer Table (Inherits from Person)
CREATE TABLE Customer (
    ID NUMBER PRIMARY KEY,
    hasInsurance CHAR(1) NOT NULL,
    Date_of_Birth DATE NOT NULL,
    FOREIGN KEY (ID) REFERENCES Person(ID)
);

-- 4. Item Table
CREATE TABLE Item (
    itemID NUMBER PRIMARY KEY,
    itemName VARCHAR2(100) NOT NULL,
    Quantity_InStock NUMBER NOT NULL,
    Require_Prescription CHAR(1) NOT NULL,
    Insurance_Cover CHAR(1) NOT NULL,
    Dosage VARCHAR2(50),
    Sale_Price NUMBER(10,2) NOT NULL,
    cost_price NUMBER(10,2) NOT NULL
);

-- 5. Prescription Table
CREATE TABLE Prescription (
    prescription_id NUMBER PRIMARY KEY,
    issue_date DATE NOT NULL,
    Doctor_ID NUMBER NOT NULL,
    Doctor_Name VARCHAR2(100) NOT NULL,
    Doctor_Speciality VARCHAR2(100) DEFAULT 'General',
    Doctor_Hospital_Name VARCHAR2(100) DEFAULT 'Unknown',
    Customer_ID NUMBER NOT NULL,
    Customer_Name VARCHAR2(100) NOT NULL,
    Customer_Date_of_Birth DATE NOT NULL,
    Customer_Insurance_Status VARCHAR2(1) DEFAULT 'N' CHECK (Customer_Insurance_Status IN ('Y', 'N')),
    isValid CHAR(1) DEFAULT 'Y' CHECK (isValid IN ('Y', 'N')),
    FOREIGN KEY (Doctor_ID) REFERENCES Doctor(ID),
    FOREIGN KEY (Customer_ID) REFERENCES Customer(ID)
);

-- 6. Prescription_Item Table (Many-to-Many Relationship)
CREATE TABLE Prescription_Item (
    prescription_id NUMBER,
    itemID NUMBER,
    quantity NUMBER NOT NULL,
    PRIMARY KEY (prescription_id, itemID),
    FOREIGN KEY (prescription_id) REFERENCES Prescription(prescription_id),
    FOREIGN KEY (itemID) REFERENCES Item(itemID)
);

-- 7. Sale Table
CREATE TABLE Sale (
    sale_id NUMBER PRIMARY KEY,
    sale_date DATE NOT NULL,
    total_price NUMBER(10,2),
    total_quantity NUMBER,
    purchase_method VARCHAR2(50) NOT NULL,
    Customer_ID NUMBER NULL,
    FOREIGN KEY (Customer_ID) REFERENCES Customer(ID)
);

-- 8. Sale_Item Table (Many-to-Many Relationship with quantity)
CREATE TABLE Sale_Item (
    sale_id NUMBER,
    itemID NUMBER,
    quantity NUMBER NOT NULL,
    PRIMARY KEY (sale_id, itemID),
    FOREIGN KEY (sale_id) REFERENCES Sale(sale_id),
    FOREIGN KEY (itemID) REFERENCES Item(itemID)
);

-- 9. Supplier Table
CREATE TABLE Supplier (
    supplier_id NUMBER PRIMARY KEY,
    supplier_name VARCHAR2(100) NOT NULL
);

-- 10. Order Table
CREATE TABLE Orders (
    order_id NUMBER PRIMARY KEY,
    order_date DATE NOT NULL,
    status VARCHAR2(50) NOT NULL,
    supplier_id NUMBER NOT NULL,
    FOREIGN KEY (supplier_id) REFERENCES Supplier(supplier_id)
);

-- 11. Order_Item Table (Many-to-Many Relationship)
CREATE TABLE Order_Item (
    order_id NUMBER,
    itemID NUMBER,
    quantity NUMBER NOT NULL,
    PRIMARY KEY (order_id, itemID),
    FOREIGN KEY (order_id) REFERENCES Orders(order_id),
    FOREIGN KEY (itemID) REFERENCES Item(itemID)
);

-- 12. Invoice Table (Weak Entity linked to Order)
CREATE TABLE Invoice (
    invoice_id NUMBER PRIMARY KEY,
    payment_total NUMBER(10,2) NOT NULL,
    invoice_date DATE NOT NULL,
    payment_method VARCHAR2(50) NOT NULL,
    order_id NUMBER NOT NULL,
    FOREIGN KEY (order_id) REFERENCES Orders(order_id)
);
ALTER TABLE Sale_Item
ADD CONSTRAINT chk_positive_quantity_saleitem
CHECK (quantity > 0);

ALTER TABLE Order_Item
ADD CONSTRAINT chk_positive_quantity_orderitem
CHECK (quantity > 0);



-- Reduce Stock on Sale
CREATE OR REPLACE TRIGGER Reduce_Stock_On_Sale
AFTER INSERT ON Sale_Item
FOR EACH ROW
BEGIN
    UPDATE Item
    SET Quantity_InStock = Quantity_InStock - :NEW.quantity
    WHERE itemID = :NEW.itemID;

    -- Prevent negative stock
    DECLARE
        v_Quantity_InStock NUMBER;
    BEGIN
        SELECT Quantity_InStock
        INTO v_Quantity_InStock
        FROM Item
        WHERE itemID = :NEW.itemID;

        IF v_Quantity_InStock < 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Error: Insufficient stock!');
        END IF;
    END;
END;
/

-- Update Stock on Order Completion
CREATE OR REPLACE TRIGGER Update_Stock_On_Order_Completion
AFTER UPDATE ON Orders
FOR EACH ROW
WHEN (NEW.status = 'Done' AND OLD.status != 'Done')
BEGIN
    UPDATE Item i
    SET i.Quantity_InStock = i.Quantity_InStock + 
        (SELECT SUM(oi.quantity)
         FROM Order_Item oi
         WHERE oi.itemID = i.itemID AND oi.order_id = :NEW.order_id)
    WHERE i.itemID IN (SELECT itemID FROM Order_Item WHERE order_id = :NEW.order_id);
END;
/


-- Prevent Sale If Stock Exhausted
CREATE OR REPLACE TRIGGER Prevent_Exhausted_Stock_Sale
BEFORE INSERT ON Sale_Item
FOR EACH ROW
DECLARE
    v_Stock NUMBER;
BEGIN
    SELECT Quantity_InStock INTO v_Stock
    FROM Item
    WHERE itemID = :NEW.itemID;

    IF v_Stock < :NEW.quantity THEN
        RAISE_APPLICATION_ERROR(-20002, 'Error: Insufficient stock!');
    END IF;
END;
/

-- Calculate Total Price and Quantity for Sale
CREATE OR REPLACE TRIGGER Calculate_Sale_Total
FOR INSERT OR UPDATE ON Sale_Item
COMPOUND TRIGGER

   TYPE SaleList IS TABLE OF Sale.sale_id%TYPE;
   g_sale_ids SaleList := SaleList();

   AFTER EACH ROW IS
   BEGIN
      -- Add the current sale_id to a collection if not already present
      IF g_sale_ids IS EMPTY OR g_sale_ids.EXISTS(:NEW.sale_id) = FALSE THEN
         g_sale_ids.EXTEND;
         g_sale_ids(g_sale_ids.LAST) := :NEW.sale_id;
      END IF;
   END AFTER EACH ROW;

   AFTER STATEMENT IS
      v_total_price NUMBER(10,2);
      v_total_quantity NUMBER;
   BEGIN
      FOR i IN 1..g_sale_ids.COUNT LOOP
         -- Calculate the totals for each affected sale_id
         SELECT SUM(si.quantity * i.sale_price),
                SUM(si.quantity)
           INTO v_total_price, v_total_quantity
           FROM Sale_Item si
           JOIN Item i ON si.itemID = i.itemID
          WHERE si.sale_id = g_sale_ids(i);

         -- Update the Sale table with the new totals
         UPDATE Sale
            SET total_price = v_total_price,
                total_quantity = v_total_quantity
          WHERE sale_id = g_sale_ids(i);
      END LOOP;
   END AFTER STATEMENT;

END Calculate_Sale_Total;
/


-- 1. Automatically Create Invoice When OrderStatus is "Done"
CREATE OR REPLACE TRIGGER Create_Invoice_On_Order_Completion
AFTER UPDATE ON Orders
FOR EACH ROW
WHEN (NEW.status = 'Done' AND OLD.status != 'Done')
DECLARE
    v_payment_total NUMBER;
BEGIN
    -- 2a) Calculate payment total (sum of cost_price * quantity)
    SELECT SUM(oi.quantity * i.cost_price)
      INTO v_payment_total
      FROM Order_Item oi
      JOIN Item i
        ON oi.itemID = i.itemID
     WHERE oi.order_id = :NEW.order_id;

    -- 2b) Insert the invoice record
    INSERT INTO Invoice (
      invoice_id,
      invoice_date,
      payment_total,
      payment_method,   -- because it's NOT NULL
      order_id
    )
    VALUES (
      SEQ_INVOICE_ID.NEXTVAL,
      SYSDATE,
      v_payment_total,
      'N/A',            -- or whatever default payment method you choose
      :NEW.order_id
    );
END;
/

-- 2. Validate Order Creation and Updates
CREATE OR REPLACE TRIGGER Validate_Order_Creation_And_Update
BEFORE INSERT OR UPDATE ON Orders
FOR EACH ROW
BEGIN
    -- Ensure Order Date is Not in the Future
    IF :NEW.order_date > SYSDATE THEN
        RAISE_APPLICATION_ERROR(-20010, 'Error: Order date cannot be in the future.');
    END IF;

    -- Ensure Order Status is Either "Done" or "Pending"
    IF :NEW.status NOT IN ('Done', 'Pending') THEN
        RAISE_APPLICATION_ERROR(-20011, 'Error: Order status must be either "Done" or "Pending".');
    END IF;
END;
/

-- 2. Validate Order Item on Insert
CREATE OR REPLACE TRIGGER Validate_Order_Item
BEFORE INSERT ON Order_Item
FOR EACH ROW
DECLARE
    v_item_count NUMBER;
BEGIN
    -- Ensure Item Exists
    SELECT COUNT(*)
    INTO v_item_count
    FROM Item
    WHERE itemID = :NEW.itemID;

    IF v_item_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20013, 'Error: Item with the given ID does not exist.');
    END IF;
END;
/

-- Prescription IssueDate Cannot Be More Than 3 Days Before Current Date
CREATE OR REPLACE TRIGGER Validate_Prescription_IssueDate
BEFORE INSERT OR UPDATE ON Prescription
FOR EACH ROW
BEGIN
    IF :NEW.issue_date < (SYSDATE - 3) THEN
        RAISE_APPLICATION_ERROR(-20009, 'Error: Prescription issue date cannot be more than 3 days before today.');
    END IF;
END;
/

-- Prescription IssueDate Cannot Be in the Future
CREATE OR REPLACE TRIGGER Validate_Future_Prescription_IssueDate
BEFORE INSERT OR UPDATE ON Prescription
FOR EACH ROW
BEGIN
    IF :NEW.issue_date > SYSDATE THEN
        RAISE_APPLICATION_ERROR(-20010, 'Error: Prescription issue date cannot be in the future.');
    END IF;
END;
/

-- Prevent Negative Stock Levels
CREATE OR REPLACE TRIGGER Prevent_Negative_Stock
BEFORE UPDATE ON Item
FOR EACH ROW
BEGIN
    IF :NEW.Quantity_InStock < 0 THEN
        RAISE_APPLICATION_ERROR(-20012, 'Error: Stock level cannot be negative.');
    END IF;
END;
/

CREATE OR REPLACE TRIGGER Invalidate_Prescription_On_Sale
AFTER INSERT ON Sale
FOR EACH ROW
BEGIN
    -- Mark the associated prescription as invalid
    UPDATE Prescription
    SET isValid = 'N'
    WHERE prescription_id = (SELECT DISTINCT prescription_id
                             FROM Prescription_Item pi
                             JOIN Sale_Item si ON pi.itemID = si.itemID
                             WHERE si.sale_id = :NEW.sale_id);
END;
/

CREATE OR REPLACE TRIGGER Validate_SaleItem_Prescription
BEFORE INSERT ON Sale_Item
FOR EACH ROW
DECLARE
    v_prescription_id    NUMBER;
    v_isValid            CHAR(1);
    v_require_pres       CHAR(1);
    v_customer_id        NUMBER;
BEGIN
    -------------------------------------------------------------------
    -- 1. Fetch the Customer_ID from the Sale table
    -------------------------------------------------------------------
    SELECT s.Customer_ID
      INTO v_customer_id
      FROM Sale s
     WHERE s.sale_id = :NEW.sale_id;

    -------------------------------------------------------------------
    -- 2. For this item, find the “most recent” (largest) prescription_id
    -------------------------------------------------------------------
    SELECT MAX(pi.prescription_id)
      INTO v_prescription_id
      FROM Prescription_Item pi
     WHERE pi.itemID = :NEW.itemID;

    -- If the item never appears in Prescription_Item, we consider that
    -- "no prescription found" if it requires one. 
    -- We'll handle that in step #3.

    -------------------------------------------------------------------
    -- 3. Check if the item requires a prescription
    -------------------------------------------------------------------
    SELECT i.Require_Prescription
      INTO v_require_pres
      FROM Item i
     WHERE i.itemID = :NEW.itemID;

    -------------------------------------------------------------------
    -- 4. If the item requires a prescription, ensure it is found
    -------------------------------------------------------------------
    IF v_require_pres = 'Y' THEN
       -- If no prescription was found for this item
       IF v_prescription_id IS NULL THEN
           RAISE_APPLICATION_ERROR(-20021, 'Error: This item requires a prescription, but none found.');
       END IF;

       -- Also ensure the customer is not NULL
       IF v_customer_id IS NULL THEN
           RAISE_APPLICATION_ERROR(-20020, 'Error: Customer is missing for a prescription-required item.');
       END IF;

       -- Now fetch the isValid flag from that prescription
       SELECT p.isValid
         INTO v_isValid
         FROM Prescription p
        WHERE p.prescription_id = v_prescription_id;
       
       -- If that prescription is invalid => error
       IF v_isValid = 'N' THEN
           RAISE_APPLICATION_ERROR(-20020, 'Error: This prescription is no longer valid.');
       END IF;
    END IF;

END;
/

-- Add Doctor from Prescription
CREATE OR REPLACE TRIGGER trg_create_doctor
BEFORE INSERT ON Prescription
FOR EACH ROW
DECLARE
    doctor_exists NUMBER;
BEGIN
    -- Check if the doctor already exists in the Doctor table
    SELECT COUNT(*) INTO doctor_exists
    FROM Doctor
    WHERE ID = :NEW.Doctor_ID;

    -- If doctor does not exist, insert into Person and Doctor tables
    IF doctor_exists = 0 THEN
        INSERT INTO Person (ID, Name) 
        VALUES (:NEW.Doctor_ID, NVL(:NEW.Doctor_Name, 'Unknown'));

        INSERT INTO Doctor (ID, Speciality, Hospital_Name) 
        VALUES (:NEW.Doctor_ID, 
                NVL(:NEW.Doctor_Speciality, 'General'), 
                NVL(:NEW.Doctor_Hospital_Name, 'Unknown'));
    END IF;
END;
/

-- Add customer from Prescription
CREATE OR REPLACE TRIGGER trg_create_customer
BEFORE INSERT ON Prescription
FOR EACH ROW
DECLARE
    customer_exists NUMBER;
BEGIN
    -- Check if the customer already exists in the Customer table
    SELECT COUNT(*) INTO customer_exists
    FROM Customer
    WHERE ID = :NEW.Customer_ID;

    -- If customer does not exist, insert into Person and Customer tables
    IF customer_exists = 0 THEN
        INSERT INTO Person (ID, Name) 
        VALUES (:NEW.Customer_ID, NVL(:NEW.Customer_Name, 'Unknown'));

        INSERT INTO Customer (ID, hasInsurance, Date_of_Birth) 
        VALUES (:NEW.Customer_ID, 
                NVL(:NEW.Customer_Insurance_Status, 'N'), 
                NVL(:NEW.Customer_Date_of_Birth, SYSDATE - 365*30)); -- Default DOB: 30 years ago
    END IF;
END;
/

-- Populate Item Table
INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (1, 'Paracetamol', 500, 'Y', 'Y', '500mg', 5.00, 2.50);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (2, 'Ibuprofen', 300, 'Y', 'N', '200mg', 8.00, 4.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (3, 'Cough Syrup', 150, 'N', 'N', '10ml', 10.00, 6.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (4, 'Antibiotic A', 200, 'Y', 'Y', '250mg', 20.00, 10.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (5, 'Antibiotic B', 250, 'Y', 'N', '500mg', 25.00, 12.50);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (6, 'Vitamin C', 1000, 'N', 'N', '500mg', 3.00, 1.50);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (7, 'Pain Relief Gel', 120, 'N', 'N', '50g', 15.00, 8.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (8, 'Allergy Medicine', 400, 'N', 'Y', '10mg', 12.00, 6.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (9, 'Antiseptic Cream', 180, 'N', 'N', '25g', 7.00, 3.50);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (10, 'Digestive Enzyme', 300, 'N', 'N', '100mg', 9.00, 4.50);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (11, 'Multivitamin', 500, 'N', 'N', '1 Tablet', 2.00, 1.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (12, 'Blood Pressure Medicine', 350, 'Y', 'Y', '50mg', 30.00, 15.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (13, 'Cholesterol Medicine', 400, 'Y', 'Y', '20mg', 28.00, 14.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (14, 'Diabetes Medicine', 300, 'Y', 'Y', '500mg', 35.00, 17.50);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (15, 'Cold Medicine', 600, 'N', 'N', '1 Tablet', 6.00, 3.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (16, 'Energy Drink', 200, 'N', 'N', '250ml', 4.00, 2.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (17, 'Oral Rehydration Salt', 100, 'N', 'N', '1 Sachet', 2.50, 1.25);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (18, 'Anti-inflammatory Ointment', 150, 'N', 'N', '30g', 10.00, 5.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (19, 'Anti-Allergy Drops', 80, 'N', 'Y', '5ml', 18.00, 9.00);

INSERT INTO Item (itemID, itemName, Quantity_InStock, Require_Prescription, Insurance_Cover, Dosage, Sale_Price, cost_price) 
VALUES (20, 'Pain Relief Spray', 50, 'N', 'N', '100ml', 25.00, 12.50);




-- Populate Supplier Table
INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (1, 'Health Pharma Co.');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (2, 'Care Supplies Ltd.');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (3, 'Wellness Distributors');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (4, 'MediCore Inc.');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (5, 'VitalMed Supply Chain');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (6, 'FastAid Wholesale');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (7, 'Global Health Partners');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (8, 'MedLife Group');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (9, 'PharmaPlus Ltd.');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (10, 'Essential Drugs Inc.');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (11, 'Rapid Care Suppliers');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (12, 'Prime Pharma');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (13, 'NextGen Medicals');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (14, 'Advanced Health Solutions');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (15, 'Universal Pharmacy Supplies');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (16, 'SmartMed Distributors');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (17, 'Elite Health Products');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (18, 'Pure Pharma Co.');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (19, 'QuickMed Corp.');

INSERT INTO Supplier (supplier_id, supplier_name) 
VALUES (20, 'Pioneer Medical Supplies');





-- Populate Orders Table
INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (1, SYSDATE - 10, 'Pending', 1);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (2, SYSDATE - 20, 'Pending', 2);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (3, SYSDATE - 15, 'Pending', 3);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (4, SYSDATE - 25, 'Pending', 4);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (5, SYSDATE - 5, 'Pending', 5);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (6, SYSDATE - 12, 'Pending', 6);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (7, SYSDATE - 8, 'Pending', 7);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (8, SYSDATE - 18, 'Pending', 8);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (9, SYSDATE - 22, 'Pending', 9);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (10, SYSDATE - 30, 'Pending', 10);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (11, SYSDATE - 7, 'Pending', 11);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (12, SYSDATE - 14, 'Pending', 12);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (13, SYSDATE - 9, 'Pending', 13);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (14, SYSDATE - 19, 'Pending', 14);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (15, SYSDATE - 3, 'Pending', 15);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (16, SYSDATE - 16, 'Pending', 16);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (17, SYSDATE - 4, 'Pending', 17);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (18, SYSDATE - 21, 'Pending', 18);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (19, SYSDATE - 6, 'Pending', 19);

INSERT INTO Orders (order_id, order_date, status, supplier_id) 
VALUES (20, SYSDATE - 11, 'Pending', 20);





-- Populate Order_Item Table
-- Order 1
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (1, 1, 50);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (1, 2, 30);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (1, 3, 20);

-- Order 2
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (2, 4, 25);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (2, 5, 15);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (2, 6, 10);

-- Order 3
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (3, 7, 20);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (3, 8, 30);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (3, 9, 25);

-- Order 4
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (4, 10, 40);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (4, 11, 50);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (4, 12, 35);

-- Order 5
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (5, 13, 20);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (5, 14, 25);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (5, 15, 30);

-- Order 6
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (6, 16, 10);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (6, 17, 15);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (6, 18, 5);

-- Order 7
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (7, 19, 20);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (7, 20, 10);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (7, 1, 30);

-- Order 8
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (8, 2, 25);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (8, 3, 15);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (8, 4, 20);

-- Order 9
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (9, 5, 35);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (9, 6, 40);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (9, 7, 25);

-- Order 10
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (10, 8, 20);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (10, 9, 15);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (10, 10, 50);

-- Order 11
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (11, 11, 30);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (11, 12, 25);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (11, 13, 20);

-- Order 12
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (12, 14, 15);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (12, 15, 10);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (12, 16, 25);

-- Order 13
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (13, 17, 30);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (13, 18, 20);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (13, 19, 15);

-- Order 14
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (14, 20, 10);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (14, 1, 50);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (14, 2, 30);

-- Order 15
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (15, 3, 25);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (15, 4, 20);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (15, 5, 35);

-- Order 16
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (16, 6, 40);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (16, 7, 25);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (16, 8, 20);

-- Order 17
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (17, 9, 15);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (17, 10, 50);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (17, 11, 30);

-- Order 18
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (18, 12, 25);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (18, 13, 20);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (18, 14, 15);

-- Order 19
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (19, 15, 10);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (19, 16, 25);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (19, 17, 30);

-- Order 20
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (20, 18, 20);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (20, 19, 15);
INSERT INTO Order_Item (order_id, itemID, quantity) VALUES (20, 20, 10);




-- Populate Prescription Table
INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (1, SYSDATE - 2, 101, 'Dr. Smith', 'Pediatrics', 'City Hospital', 201, 'Alice Brown', TO_DATE('1990-03-25', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (2, SYSDATE - 3, 102, 'Dr. Johnson', 'Dermatology', 'Health Clinic', 202, 'Bob Green', TO_DATE('1985-07-12', 'YYYY-MM-DD'), 'N', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (3, SYSDATE - 1, 103, 'Dr. Lee', 'Cardiology', 'Heart Center', 203, 'Carol White', TO_DATE('1975-11-05', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (4, SYSDATE - 4, 104, 'Dr. Miller', 'Orthopedics', 'General Hospital', 204, 'David Black', TO_DATE('1992-08-19', 'YYYY-MM-DD'), 'N', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (5, SYSDATE - 2, 105, 'Dr. Garcia', 'Neurology', 'Brain Institute', 205, 'Eve Blue', TO_DATE('1988-01-30', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (6, SYSDATE - 1, 106, 'Dr. Walker', 'Oncology', 'Cancer Care', 206, 'Frank Yellow', TO_DATE('1980-10-15', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (7, SYSDATE - 3, 107, 'Dr. Harris', 'Gastroenterology', 'St. Mary Hospital', 207, 'Grace Red', TO_DATE('1995-04-20', 'YYYY-MM-DD'), 'N', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (8, SYSDATE - 2, 108, 'Dr. Adams', 'Endocrinology', 'Specialist Center', 208, 'Henry Orange', TO_DATE('1978-06-11', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (9, SYSDATE - 4, 109, 'Dr. Baker', 'Rheumatology', 'Wellness Center', 209, 'Ivy Pink', TO_DATE('1982-09-08', 'YYYY-MM-DD'), 'N', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (10, SYSDATE - 1, 110, 'Dr. Carter', 'Pulmonology', 'Breath Clinic', 210, 'Jack Purple', TO_DATE('1991-12-03', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (11, SYSDATE - 3, 111, 'Dr. Collins', 'Nephrology', 'Kidney Care', 211, 'Kate Gray', TO_DATE('1984-05-17', 'YYYY-MM-DD'), 'N', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (12, SYSDATE - 2, 112, 'Dr. Evans', 'Urology', 'Mens Health Center', 212, 'Leo Brown', TO_DATE('1987-02-22', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (13, SYSDATE - 1, 113, 'Dr. Foster', 'Hematology', 'Blood Institute', 213, 'Mona White', TO_DATE('1993-07-07', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (14, SYSDATE - 3, 114, 'Dr. Gonzalez', 'Ophthalmology', 'Vision Clinic', 214, 'Nate Black', TO_DATE('1979-10-14', 'YYYY-MM-DD'), 'N', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (15, SYSDATE - 2, 115, 'Dr. Hayes', 'Radiology', 'Imaging Center', 215, 'Olive Blue', TO_DATE('1986-03-01', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (16, SYSDATE - 1, 116, 'Dr. James', 'Allergy and Immunology', 'Allergy Center', 216, 'Paul Yellow', TO_DATE('1994-08-30', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (17, SYSDATE - 4, 117, 'Dr. King', 'Internal Medicine', 'Community Clinic', 217, 'Quinn Red', TO_DATE('1983-06-25', 'YYYY-MM-DD'), 'N', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (18, SYSDATE - 3, 118, 'Dr. Lewis', 'Family Medicine', 'Family Health', 218, 'Rose Orange', TO_DATE('1990-12-15', 'YYYY-MM-DD'), 'Y', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (19, SYSDATE - 2, 119, 'Dr. Martin', 'Emergency Medicine', 'ER Hospital', 219, 'Sam Pink', TO_DATE('1981-05-20', 'YYYY-MM-DD'), 'N', 'Y');

INSERT INTO Prescription (prescription_id, issue_date, Doctor_ID, Doctor_Name, Doctor_Speciality, Doctor_Hospital_Name, Customer_ID, Customer_Name, Customer_Date_of_Birth, Customer_Insurance_Status, isValid) 
VALUES (20, SYSDATE - 1, 120, 'Dr. Nelson', 'Dermatology', 'Skin Clinic', 220, 'Tina Purple', TO_DATE('1989-11-09', 'YYYY-MM-DD'), 'Y', 'Y');


-- Populate Prescriptions
-- Prescription 1
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (1, 1, 10);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (1, 6, 5);

-- Prescription 2
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (2, 2, 8);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (2, 3, 4);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (2, 9, 2);

-- Prescription 3
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (3, 4, 7);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (3, 5, 3);

-- Prescription 4
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (4, 7, 6);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (4, 10, 2);

-- Prescription 5
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (5, 11, 12);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (5, 12, 4);

-- Prescription 6
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (6, 13, 5);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (6, 14, 3);

-- Prescription 7
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (7, 15, 9);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (7, 16, 2);

-- Prescription 8
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (8, 17, 4);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (8, 18, 6);

-- Prescription 9
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (9, 19, 3);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (9, 20, 1);

-- Prescription 10
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (10, 1, 5);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (10, 2, 7);

-- Prescription 11
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (11, 3, 6);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (11, 4, 2);

-- Prescription 12
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (12, 5, 8);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (12, 6, 4);

-- Prescription 13
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (13, 7, 10);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (13, 8, 3);

-- Prescription 14
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (14, 9, 5);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (14, 10, 2);

-- Prescription 15
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (15, 11, 7);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (15, 12, 3);

-- Prescription 16
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (16, 13, 4);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (16, 14, 5);

-- Prescription 17
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (17, 15, 6);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (17, 16, 2);

-- Prescription 18
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (18, 17, 3);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (18, 18, 4);

-- Prescription 19
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (19, 19, 2);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (19, 20, 3);

-- Prescription 20
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (20, 1, 4);
INSERT INTO Prescription_Item (prescription_id, itemID, quantity) VALUES (20, 2, 6);

-- Populate Sale Table
INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (1, SYSDATE - 5, 'Cash', 201);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (2, SYSDATE - 6, 'Card', 202);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (3, SYSDATE - 4, 'Cash', 203);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (4, SYSDATE - 7, 'Online', 204);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (5, SYSDATE - 3, 'Card', 205);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (6, SYSDATE - 2, 'Online', 206);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (7, SYSDATE - 8, 'Cash', 207);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (8, SYSDATE - 9, 'Card', 208);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (9, SYSDATE - 10, 'Online', 209);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (10, SYSDATE - 1, 'Cash', 210);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (11, SYSDATE - 5, 'Cash', 211);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (12, SYSDATE - 6, 'Card', 212);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (13, SYSDATE - 4, 'Cash', 213);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (14, SYSDATE - 7, 'Online', 214);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (15, SYSDATE - 3, 'Card', 215);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (16, SYSDATE - 2, 'Online', 216);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (17, SYSDATE - 8, 'Cash', 217);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (18, SYSDATE - 9, 'Card', 218);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (19, SYSDATE - 10, 'Online', 219);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (20, SYSDATE - 1, 'Cash', 220);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (21, SYSDATE - 2, 'Online', NULL);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (22, SYSDATE - 8, 'Cash', NULL);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (23, SYSDATE - 9, 'Card', NULL);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (24, SYSDATE - 10, 'Online', NULL);

INSERT INTO Sale (sale_id, sale_date, purchase_method, Customer_ID) 
VALUES (25, SYSDATE - 1, 'Cash', NULL);




-- Populate Sale_Items
-- Sale 1
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (1, 1, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (1, 12, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (1, 15, 5);

-- Sale 2
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (2, 2, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (2, 13, 5);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (2, 5, 4);

-- Sale 3
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (3, 3, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (3, 6, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (3, 7, 2);

-- Sale 4
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (4, 4, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (4, 8, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (4, 9, 2);

-- Sale 5
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (5, 10, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (5, 14, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (5, 15, 2);

-- Sale 6
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (6, 16, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (6, 17, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (6, 18, 1);

-- Sale 7
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (7, 11, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (7, 19, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (7, 20, 2);

-- Sale 8
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (8, 1, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (8, 3, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (8, 12, 6);

-- Sale 9
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (9, 2, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (9, 4, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (9, 13, 4);

-- Sale 10
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (10, 5, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (10, 6, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (10, 7, 1);

-- Sale 11
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (11, 1, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (11, 12, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (11, 15, 5);

-- Sale 12
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (12, 2, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (12, 13, 5);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (12, 5, 4);

-- Sale 13
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (13, 3, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (13, 6, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (13, 7, 2);

-- Sale 14
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (14, 4, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (14, 8, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (14, 9, 2);

-- Sale 15
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (15, 10, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (15, 14, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (15, 15, 2);

-- Sale 16
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (16, 16, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (16, 17, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (16, 18, 1);

-- Sale 17
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (17, 11, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (17, 19, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (17, 20, 2);

-- Sale 18
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (18, 1, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (18, 3, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (18, 12, 6);

-- Sale 19
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (19, 2, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (19, 4, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (19, 13, 4);

-- Sale 20
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (20, 5, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (20, 6, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (20, 7, 1);

-- Sale 21
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (21, 11, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (21, 19, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (21, 20, 2);

-- Sale 22
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (22, 1, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (22, 3, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (22, 12, 6);

-- Sale 23
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (23, 2, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (23, 4, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (23, 13, 4);

-- Sale 24
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (24, 5, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (24, 6, 1);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (24, 7, 1);

-- Sale 25
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (25, 1, 2);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (25, 12, 3);
INSERT INTO Sale_Item (sale_id, itemID, quantity) VALUES (25, 15, 5);

UPDATE Orders
SET status = 'Done'
WHERE order_id IN (1, 3, 5);