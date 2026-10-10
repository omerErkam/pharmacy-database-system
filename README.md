# Pharmacy Database System

## Project Overview
The Pharmacy Database System provides a comprehensive, integrated data management solution tailored specifically for a small, single-user pharmacy[cite: 1, 2]. The core business problem this project solves is the manual, error-prone handling of daily pharmacy operations. This system streamlines inventory tracking, supplier management, prescription record-keeping, and sales processing[cite: 1, 2]. By replacing manual workflows with automated SQL triggers for invoicing and stock updates, the database ensures data consistency, enhances operational accuracy, and maintains strict regulatory compliance[cite: 1, 2].

## Tech Stack & Tools
* **Programming Languages:** SQL
* **Database Environment:** Oracle APEX (Application Express)
* **Data Modeling:** Entity-Relationship (ER) Modeling, Relational Schemas

## Methodology
1. **Architectural Design & Data Modeling:** Designed an Entity-Relationship (ER) diagram and a relational schema consisting of over a dozen interconnected tables (e.g., Sale, Item, Prescription, Supplier, Order). Implemented an inheritance hierarchy where `Doctor` and `Customer` inherit shared attributes from a generalized `Person` entity[cite: 2, 3].
2. **Database Instantiation:** Executed Data Definition Language (DDL) scripts to build the tables and enforce primary/foreign key constraints, ensuring structural data integrity across all entities.
3. **Workflow Automation (Triggers):** Programmed SQL triggers to handle background business logic without manual intervention[cite: 2]. Key automated flows include automatically updating inventory stock when an order is completed, and generating invoices automatically upon order completion[cite: 1, 2].
4. **Data Analytics & Business Intelligence:** Developed complex analytical SQL queries utilizing `JOIN` operations and nested subqueries to extract actionable business insights[cite: 2]. These queries track revenue by customer, identify top-selling non-prescribed items, and analyze the most active suppliers[cite: 1, 2].

## Results & Evaluation
* Successfully executed 281 out of 310 SQL statements in Oracle APEX to seamlessly configure the database schema, populate initial mock data, and deploy automated triggers[cite: 2].
* Established a robust, automated pipeline for stock and invoice management that prevents data entry errors and inventory desynchronization[cite: 2].
