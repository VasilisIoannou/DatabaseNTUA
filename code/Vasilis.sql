/* After you Insert to Reselling Tickets or to desired by event */
/* Check if there any matches to do the transaction */
DELIMITER //

CREATE PROCEDURE process_ticket_matches()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_ean BIGINT;
    DECLARE v_buyer_id INT;
    DECLARE v_visitor_id INT;
    DECLARE v_date_issued_id INT;
    
    -- Cursor to find all matching tickets with buyer priorities
    DECLARE match_cursor CURSOR FOR
        SELECT rt.EAN_13, d.buyer_id, b.visitor_id, d.date_issued_id
        FROM reselling_tickets rt
        JOIN ticket t ON rt.EAN_13 = t.EAN_13
        JOIN desired_ticket_by_event d ON d.event_id = t.event_id 
                                     AND d.ticket_type_id = t.ticket_type_id
        JOIN buyer b ON d.buyer_id = b.buyer_id
        WHERE t.validated = FALSE
        ORDER BY rt.EAN_13, d.date_issued_id;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    -- Create a temporary table to track processed tickets
    CREATE TEMPORARY TABLE IF NOT EXISTS processed_tickets (
        ean_13 BIGINT PRIMARY KEY
    );
    
    OPEN match_cursor;
    
    match_loop: LOOP
        FETCH match_cursor INTO v_ean, v_buyer_id, v_visitor_id, v_date_issued_id;
        IF done THEN
            LEAVE match_loop;
        END IF;
        
        -- Check if this ticket hasn't been processed yet
        IF NOT EXISTS (SELECT 1 FROM processed_tickets WHERE ean_13 = v_ean) THEN
            -- Update the ticket with new owner
            UPDATE ticket 
            SET visitor_id = v_visitor_id,
                validated = FALSE -- Keep as unvalidated until actually used
            WHERE EAN_13 = v_ean;
            
            -- Remove from reselling tickets
            DELETE FROM reselling_tickets WHERE EAN_13 = v_ean;
            
            -- Mark as processed
            INSERT INTO processed_tickets (ean_13) VALUES (v_ean);
 		
	    -- Save to ticket_tranfer log
	    INSERT INTO ticket_transfer(buyer_id,EAN_13) VALUES (v_buyer_id,v_ean);
        END IF;
    END LOOP;
    
    CLOSE match_cursor;
    DROP TEMPORARY TABLE IF EXISTS processed_tickets;
END//

DELIMITER ;

CREATE TRIGGER desired_by_id
BEFORE INSERT ON reselling_tickets FOR EACH ROW
BEGIN
	CALL check_for_matches();
END//


CREATE TRIGGER desired_ticket_by_event
BEFORE INSERT ON desired_by_id FOR EACH ROW
BEGIN
	CALL check_for_matches();
END//

