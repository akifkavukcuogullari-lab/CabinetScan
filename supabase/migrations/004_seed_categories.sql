-- ============================================
-- NEXTLEAN SCAN - SEED DATA: MASTER CATEGORIES
-- Migration: 004_seed_categories
-- ============================================

INSERT INTO categories (name, slug, description, pricing_unit, display_order, icon_name) VALUES
    ('Cabinet Model', 'cabinet-model', 'Cabinet style and configuration', 'per_linear_ft', 1, 'cabinet'),
    ('Cabinet Color', 'cabinet-color', 'Cabinet exterior color', 'none', 2, 'paintpalette'),
    ('Cabinet Finish', 'cabinet-finish', 'Cabinet surface finish type', 'none', 3, 'paintbrush'),
    ('Countertop', 'countertop', 'Countertop material', 'per_sq_ft', 4, 'square.split.2x2'),
    ('Countertop Edge', 'countertop-edge', 'Edge profile for countertops', 'per_linear_ft', 5, 'ruler'),
    ('Hardware', 'hardware', 'Cabinet handles and knobs', 'per_piece', 6, 'wrench.and.screwdriver'),
    ('Backsplash', 'backsplash', 'Wall backsplash material', 'per_sq_ft', 7, 'square.grid.3x3'),
    ('Sink', 'sink', 'Kitchen or bathroom sink', 'per_piece', 8, 'drop'),
    ('Faucet', 'faucet', 'Sink faucet fixture', 'per_piece', 9, 'drop.circle'),
    ('Cabinet Lighting', 'cabinet-lighting', 'Under-cabinet lighting', 'per_linear_ft', 10, 'light.max'),
    ('Crown Molding', 'crown-molding', 'Decorative crown molding', 'per_linear_ft', 11, 'square.topthird.inset.filled'),
    ('Toe Kick', 'toe-kick', 'Cabinet base trim', 'per_linear_ft', 12, 'square.bottomthird.inset.filled'),
    ('Soft-Close Hinges', 'soft-close-hinges', 'Quiet-close door hinges', 'per_cabinet', 13, 'door.left.hand.closed'),
    ('Pull-out Organizers', 'pull-out-organizers', 'Interior cabinet organizers', 'per_piece', 14, 'tray.2');
