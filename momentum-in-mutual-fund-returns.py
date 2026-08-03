// QuantConnect Logo
# QuantBook Analysis Tool 
# For more information see [https://www.quantconnect.com/docs/research/overview]
qb = QuantBook()
spy = qb.AddEquity("SPY")
history = qb.History(qb.Securities.Keys, 360, Resolution.Daily)

# Indicator Analysis
bbdf = qb.Indicator(BollingerBands(30, 2), spy.Symbol, 360, Resolution.Daily)
bbdf.drop('standarddeviation', 1).plot()
 

# https://quantpedia.com/strategies/momentum-in-mutual-fund-returns/
#



# The investment universe consists of equity funds from the CRSP Mutual Fund database.
# This universe is then shrunk to no-load funds (to remove entrance fees).
# Investors then sort mutual funds based on their past 6-month return and divide them into deciles.
# The top decile of mutual funds is then picked into an investment portfolio (equally weighted), and funds are held for three months.
# Other measures of momentum could also be used in sorting (fund’s closeness to 1 year high in NAV and momentum factor loading),
# and it is highly probable that the combined predictor would have even better results than only the simple 6-month momentum.
#
# QC Implementation:
#   - Universe consist of approximately 850 mutual funds.

#region imports
from AlgorithmImports import *
#endregion

class MomentuminMutualFundReturns(QCAlgorithm):

    def Initialize(self) -> None:
        # NOTE: most of the data start from 2014 and until 2015 there wasn't any trade
        self.SetStartDate(2014, 1, 1)
        self.SetCash(100_000)
        
        self.data: Dict[str, RollingWindow] = {}
        self.symbols: List[str] = []
        
        leverage: int = 5
        self.period: int = 21 * 6 # Storing 6 months of daily prices
        self.quantile: int = 10
        
        self.symbol: Symbol = self.AddEquity('SPY', Resolution.Daily).Symbol
        
        # Load csv file with etf symbols and split line with semi-colon
        etf_symbols_csv: str = self.Download("data.quantpedia.com/backtesting_data/equity/mutual_funds/symbols.csv")
        splitted_csv: List[str] = etf_symbols_csv.split(';')
        
        for symbol in splitted_csv[:500]:
            self.symbols.append(symbol)
            
            # Subscribe for QuantpediaETF by etf symbol, then set fee model and leverage
            data: Security = self.AddData(QuantpediaETF, symbol, Resolution.Daily)
            data.SetFeeModel(CustomFeeModel())
            data.SetLeverage(leverage)
            
            self.data[symbol] = RollingWindow[float](self.period)
        
        self.recent_month: int = -1

    def OnData(self, slice: Slice) -> None:
        funds_last_update_date: Dict[str, datetime.date] = QuantpediaETF.get_last_update_date()

        # Update daily prices of etfs
        for symbol in self.symbols:
            if slice.contains_key(symbol) and slice[symbol]:
                price: float = slice[symbol].Value
                self.data[symbol].Add(price)

        if self.recent_month == self.Time.month:
            return
        self.recent_month = self.Time.month

        # Rebalance quarterly
        if self.recent_month % 3 != 0:
            return
            
        performance: Dict[str, float] = {}
        
        for symbol in self.symbols:
            # If data for etf are ready calculate it's 6 month performance
            if self.data[symbol].IsReady:
                if self.Securities[symbol].GetLastData() and self.time.date() < funds_last_update_date[symbol]:
                    prices: List[float] = [x for x in self.data[symbol]]
                    performance[symbol] = (prices[0] - prices[-1]) / prices[-1]
                
        if len(performance) < self.quantile:
            self.Liquidate()
            return
        
        quantile: int = int(len(performance) / self.quantile)
        # sort dictionary by performance and based on it create sorted list
        sorted_by_perf: List[str] = [x[0] for x in sorted(performance.items(), key=lambda item: item[1], reverse=True)]
        # select top decile etfs for investment based on performance
        long: List[str] = sorted_by_perf[:quantile]
        
        # Trade execution
        targets: List[PortfolioTarget] = []
        for symbol in long:
            if slice.contains_key(symbol) and slice[symbol]:
                targets.append(PortfolioTarget(symbol, 1 / len(long)))
        
        self.SetHoldings(targets, True)

# Quantpedia data
# NOTE: IMPORTANT: Data order must be ascending (datewise)
class QuantpediaETF(PythonData):
    _last_update_date:Dict[Symbol, datetime.date] = {}

    @staticmethod
    def get_last_update_date() -> Dict[Symbol, datetime.date]:
       return QuantpediaETF._last_update_date

    def GetSource(self, config: SubscriptionDataConfig, date: datetime, isLiveMode: bool) -> SubscriptionDataSource:
        return SubscriptionDataSource("data.quantpedia.com/backtesting_data/equity/mutual_funds/{0}.csv".format(config.Symbol.Value), SubscriptionTransportMedium.RemoteFile, FileFormat.Csv)

    def Reader(self, config: SubscriptionDataConfig, line: str, date: datetime, isLiveMode: bool) -> BaseData:
        data = QuantpediaETF()
        data.Symbol = config.Symbol
        
        if not line[0].isdigit(): return None
        split = line.split(';')
        
        data.Time = datetime.strptime(split[0], "%d.%m.%Y") + timedelta(days=1)
        data['settle'] = float(split[1])
        data.Value = float(split[1])

        if config.Symbol.Value not in QuantpediaETF._last_update_date:
            QuantpediaETF._last_update_date[config.Symbol.Value] = datetime(1,1,1).date()
        if data.Time.date() > QuantpediaETF._last_update_date[config.Symbol.Value]:
            QuantpediaETF._last_update_date[config.Symbol.Value] = data.Time.date()

        return data

# Custom fee model
class CustomFeeModel(FeeModel):
    def GetOrderFee(self, parameters: OrderFeeParameters) -> OrderFee:
        fee: float = parameters.Security.Price * parameters.Order.AbsoluteQuantity * 0.00005
        return OrderFee(CashAmount(fee, "USD"))