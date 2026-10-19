import { Router, Request, Response } from 'express';

const router = Router();

// In-memory persistent state for the backend service session
let cards = [
  {
    id: 'card_wps',
    title: 'WPS Payroll Card',
    provider_name: 'Wage Protection System (Al Rajhi)',
    card_number_masked: '•••• 8420',
    balance: 98420.12,
    currency: 'BDT',
    expiry_date: '08/29',
    card_type: 'wpsPayroll',
  },
  {
    id: 'card_probashi',
    title: 'Probashi Expatriate Account',
    provider_name: 'Probashi Kallyan Bank',
    card_number_masked: '•••• 1947',
    balance: 145000.0,
    currency: 'BDT',
    expiry_date: '12/28',
    card_type: 'probashiMultiCurrency',
  },
  {
    id: 'card_visa',
    title: 'Probashi Global Visa',
    provider_name: 'Visa • International',
    card_number_masked: '•••• 4242',
    balance: 24850.5,
    currency: 'BDT',
    expiry_date: '03/30',
    card_type: 'internationalVisa',
  },
];

let beneficiaries = [
  {
    id: 'ben_1',
    name: 'Elizabeth',
    phone_or_account: '+880 1712-345678',
    provider_type: 'bKash',
    avatar_url: '',
    initials: 'EL',
    is_recent: true,
    country_code: 'BD',
    country_flag: '🇧🇩',
    country_name: 'Bangladesh',
    country_dial_code: '+880',
    currency: 'BDT',
    currency_symbol: '৳',
  },
  {
    id: 'ben_2',
    name: 'William',
    phone_or_account: '+966 55 123 4567',
    provider_type: 'STC Pay',
    avatar_url: '',
    initials: 'WI',
    is_recent: true,
    country_code: 'SA',
    country_flag: '🇸🇦',
    country_name: 'Saudi Arabia',
    country_dial_code: '+966',
    currency: 'SAR',
    currency_symbol: '﷼',
  },
  {
    id: 'ben_3',
    name: 'Adam',
    phone_or_account: '+971 50 987 6543',
    provider_type: 'Careem Pay',
    avatar_url: '',
    initials: 'AD',
    is_recent: true,
    country_code: 'AE',
    country_flag: '🇦🇪',
    country_name: 'United Arab Emirates',
    country_dial_code: '+971',
    currency: 'AED',
    currency_symbol: 'د.إ',
  },
  {
    id: 'ben_4',
    name: 'Tony',
    phone_or_account: '+974 33 112 233',
    provider_type: 'Ooredoo Money',
    avatar_url: '',
    initials: 'TO',
    is_recent: true,
    country_code: 'QA',
    country_flag: '🇶🇦',
    country_name: 'Qatar',
    country_dial_code: '+974',
    currency: 'QAR',
    currency_symbol: 'ر.ق',
  },
];

let transactions = [
  {
    id: 'tx_1',
    title: 'Google',
    subtitle: 'Subscription',
    amount: 60.0,
    currency: 'USD',
    timestamp: new Date(Date.now() - 42 * 60000).toISOString(),
    type: 'subscription',
    card_id: 'card_wps',
    icon_category: 'google',
  },
  {
    id: 'tx_2',
    title: 'Elizabeth',
    subtitle: 'Received Money',
    amount: 420.0,
    currency: 'USD',
    timestamp: new Date(Date.now() - 192 * 60000).toISOString(),
    type: 'receive',
    card_id: 'card_wps',
    icon_category: 'person',
  },
  {
    id: 'tx_3',
    title: 'WPS Wage Credit',
    subtitle: 'Monthly Employer Salary',
    amount: 3250.0,
    currency: 'SAR',
    timestamp: new Date(Date.now() - 2 * 86400000).toISOString(),
    type: 'receive',
    card_id: 'card_wps',
    icon_category: 'salary',
  },
  {
    id: 'tx_4',
    title: 'Family Remittance',
    subtitle: 'bKash Bangladesh Transfer',
    amount: 35000.0,
    currency: 'BDT',
    timestamp: new Date(Date.now() - 4 * 86400000).toISOString(),
    type: 'send',
    card_id: 'card_visa',
    icon_category: 'remittance',
  },
];

/**
 * GET /api/payment/cards
 */
router.get('/cards', (_req: Request, res: Response) => {
  res.json({ cards });
});

/**
 * GET /api/payment/beneficiaries
 */
router.get('/beneficiaries', (_req: Request, res: Response) => {
  res.json({ beneficiaries });
});

/**
 * GET /api/payment/transactions
 */
router.get('/transactions', (req: Request, res: Response) => {
  const cardId = req.query.cardId as string | undefined;
  if (cardId) {
    return res.json({ transactions: transactions.filter((tx) => tx.card_id === cardId) });
  }
  res.json({ transactions });
});

/**
 * POST /api/payment/transfer-cards
 */
router.post('/transfer-cards', (req: Request, res: Response) => {
  const { fromCardId, toCardId, amount } = req.body;
  const fromIndex = cards.findIndex((c) => c.id === fromCardId);
  const toIndex = cards.findIndex((c) => c.id === toCardId);

  if (fromIndex === -1 || toIndex === -1) {
    return res.status(404).json({ success: false, error: 'Card not found' });
  }

  if (cards[fromIndex].balance < amount) {
    return res.status(400).json({ success: false, error: 'Insufficient funds' });
  }

  cards[fromIndex].balance -= amount;
  cards[toIndex].balance += amount;

  const transferTx = {
    id: `tx_${Date.now()}`,
    title: 'Inter-Card Swap',
    subtitle: `${cards[fromIndex].title} → ${cards[toIndex].title}`,
    amount,
    currency: 'BDT',
    timestamp: new Date().toISOString(),
    type: 'transfer',
    card_id: fromCardId,
    icon_category: 'transfer',
  };

  transactions.unshift(transferTx);

  res.json({ success: true, transaction: transferTx, cards });
});

export default router;
