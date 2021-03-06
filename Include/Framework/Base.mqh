//+------------------------------------------------------------------+
//|                                   Copyright 2016, Erlon F. Souza |
//|                                       https://github.com/erlonfs |
//+------------------------------------------------------------------+

#property copyright "Copyright 2016, Erlon F. Souza"
#property link      "https://github.com/erlonfs"
#define   version    "1.7.0" 

#include <Trade\Trade.mqh>

class Base
{

private:

	//Definicoes Basicas
	string _symbol;
	double _volume;
	double _spread;
	double _stopGain;
	double _stopLoss;
	ENUM_TIMEFRAMES _period;
	bool _isClosePosition;
	
	//Stop no candle anterior
	bool _isStopOnLastCandle;
	double _spreadStopOnLastCandle;
	MqlRates _rates[];

	//Trailing Stop
	bool _isTrailingStop;
	double _trailingStopInicio;
	double _trailingStop;

	//Break Even
	bool _isBreakEven;
	double _breakEvenInicio;
	double _breakEven;	

	//Parciais
	bool _isParcial;
	double _isPrimeiraParcial;
	double _primeiraParcialVolume;
	double _primeiraParcialInicio;
	double _isSegundaParcial;
	double _segundaParcialVolume;
	double _segundaParcialInicio;
	double _isTerceiraParcial;
	double _terceiraParcialVolume;
	double _terceiraParcialInicio;

	//Gerenciamento Financeiro
	bool _isGerenciamentoFinanceiro;
	double _totalProfitMoney;
	double _totalStopLossMoney;
	double _totalOrdensVolume;
	double _corretagemValor;
	bool _isCalcularCorretagemValoresMaximosDiarios;
	double _maximoLucroDiario;
	double _maximoPrejuizoDiario;

	//Outros
	string _robotName;	
	string _robotVersion;
	string _lastText;
	string _lastTextValidate;
	MqlTick _lastPrice;
	CTrade _trade;
	CPositionInfo _position;
	string _info;
	bool _isNotificacoesApp;
	
	MqlDateTime _timeCurrent;
	MqlDateTime _horaInicio;
	MqlDateTime _horaFim;
	MqlDateTime _horaInicioIntervalo;
	MqlDateTime _horaFimIntervalo;
	
	string _horaInicioString;
	string _horaFimString;
	string _horaInicioIntervaloString;
	string _horaFimIntervaloString;
	
	//Auxiliares
	bool _isBusy;
	bool _isNewCandle;
	
	void ManagePosition() {
	
	   if(_isBusy) return;
	   
	   _isBusy = true;

		if (GetPositionMagicNumber() != _trade.RequestMagic()) {
			return;
		}

		if (_isClosePosition) {
			if (GetHoraFim().hour == GetTimeCurrent().hour) {
				if (GetHoraFim().min >= GetTimeCurrent().min) {
					ClosePosition();
				}
			}
		}
								
		ManageStopOnLastCandle();
		ManageTrailingStop();
		ManageBreakEven();
		ManageParcial();
		ManageDrawParcial();
		
		_isBusy = false;

	}

	void RestartManagePosition() {
		_isPrimeiraParcial = false;
		_isSegundaParcial = false;
		_isTerceiraParcial = false;
	}	
	
	void AtualizarQuantidadesStopsAndGains() {

		string CurrDate = TimeToString(TimeCurrent(), TIME_DATE);
		HistorySelect(StringToTime(CurrDate), TimeCurrent());

		uint total = HistoryDealsTotal();
		ulong ticket = 0;
		double price;
		double profit;
		datetime time;
		string symbol;
		string comment;
		long type;
		long entry;
		double volume;
		ulong magic;

		double totalGainMoney = 0.0;
		double totalLossMoney = 0.0;
		double qtdOrdensVolume = 0;

		for (int i = HistoryDealsTotal() - 1; i >= 0; i--)
		{
			ticket = HistoryDealGetTicket(i);

			if (ticket <= 0) {
				continue;
			}

			price = HistoryDealGetDouble(ticket, DEAL_PRICE);
			time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
			symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
			comment = HistoryDealGetString(ticket, DEAL_COMMENT);
			type = HistoryDealGetInteger(ticket, DEAL_TYPE);
			magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
			entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
			profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
			volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);

			if (symbol != _symbol) {
				continue;
			}

			if (magic != _trade.RequestMagic()) {
				continue;
			}

			if (!price && !time) {
				continue;
			}

			if (profit < 0) {
				totalLossMoney += profit;
				qtdOrdensVolume += volume;
				continue;
			}

			if (profit > 0) {
				totalGainMoney += profit;
				qtdOrdensVolume += volume;
				continue;
			}

		}

		_totalProfitMoney = totalGainMoney;
		_totalStopLossMoney = totalLossMoney;
		_totalOrdensVolume = qtdOrdensVolume;


	}
	
	bool ManageStopOnLastCandle(){
	   
	   if (!_isStopOnLastCandle || !_isNewCandle) {
			return false;
		}	
		
		if(CopyRates(GetSymbol(), GetPeriod(), 0, 2, _rates) <= 0){
		   return false;
		}
		
		//Posicao menor é o mais longe, ou seja, _rates[0] é o primeiro e _rates[1] é o ultimo
		MqlRates _candleAnterior = _rates[0];	
		
		if (GetPositionType() == POSITION_TYPE_BUY) {

			if (GetPositionLoss() < _candleAnterior.low) {
				_trade.PositionModify(_symbol, _candleAnterior.low - GetSpreadStopOnLastCandle(), GetPositionGain());
				ShowMessage("Stop Alterado para a mínina do candle anterior! STOP LOSS " + (string)GetPositionLoss());
				return true;
			}

		}

		if (GetPositionType() == POSITION_TYPE_SELL) {

			if (GetPositionLoss() > _candleAnterior.high) {
				_trade.PositionModify(_symbol, _candleAnterior.high + GetSpreadStopOnLastCandle(), GetPositionGain());
				ShowMessage("Stop Alterado para a máxima do candle anterior! STOP LOSS " + (string)GetPositionLoss());
				return true;
			}

		}
		
		return false;
	   
	}

	bool ManageTrailingStop() {

		if (!_isTrailingStop) {
			return false;
		}

		if (GetPositionType() == POSITION_TYPE_BUY) {

			if (GetPrice().last - GetPositionLoss() >= GetStopLoss() + _trailingStopInicio) {
				_trade.PositionModify(_symbol, GetPositionLoss() + _trailingStop, GetPositionGain());
				ShowMessage("Trailing Stop Acionado! STOP LOSS " + (string)GetPositionLoss());
				return true;
			}

		}

		if (GetPositionType() == POSITION_TYPE_SELL) {

			if (GetPositionLoss() - GetPrice().last >= GetStopLoss() + _trailingStopInicio) {
				_trade.PositionModify(_symbol, GetPositionLoss() - _trailingStop, GetPositionGain());
				ShowMessage("Trailing Stop Acionado! STOP LOSS " + (string)GetPositionLoss());
				return true;
			}

		}

		return false;

	}

	bool ManageBreakEven() {

		if (!_isBreakEven) {
			return false;
		}

		if (GetPositionType() == POSITION_TYPE_BUY) {

			if (GetPrice().last >= GetPositionPriceOpen() + _breakEvenInicio && GetPositionLoss() < GetPositionPriceOpen()) {
				_trade.PositionModify(_symbol, GetPositionPriceOpen() + _breakEven, GetPositionGain());
				ShowMessage("Break Even Acionado!");
				return true;
			}
		}

		if (GetPositionType() == POSITION_TYPE_SELL) {

			if (GetPrice().last <= GetPositionPriceOpen() - _breakEvenInicio && GetPositionLoss() > GetPositionPriceOpen()) {
				_trade.PositionModify(_symbol, GetPositionPriceOpen() - _breakEven, GetPositionGain());
				ShowMessage("Break Even Acionado!");
				return true;
			}
		}

		return false;

	}

	bool ManageParcial()
	{
		if (!_isParcial) {
			return false;
		}

		double positionLoss = GetPositionLoss();
		double positionGain = GetPositionGain();

		bool isPrimeiraParcial = false;
		bool isSegundaParcial = false;
		bool isTerceiraParcial = false;

		string msg = "";

		if (GetPositionType() == POSITION_TYPE_BUY) {

			isPrimeiraParcial = GetPrice().last >= GetPositionPriceOpen() + _primeiraParcialInicio;
			isSegundaParcial = GetPrice().last >= GetPositionPriceOpen() + _segundaParcialInicio;
			isTerceiraParcial = GetPrice().last >= GetPositionPriceOpen() + _terceiraParcialInicio;

			if (isPrimeiraParcial && !_isPrimeiraParcial && _primeiraParcialInicio > 0) {
				_isPrimeiraParcial = true;
				_trade.Sell(_primeiraParcialVolume, _symbol);
				msg = "Primeira saída parcial executada!";
			}

			if (isSegundaParcial && !_isSegundaParcial && _segundaParcialInicio > 0) {
				_isSegundaParcial = true;
				_trade.Sell(_segundaParcialVolume, _symbol);
				msg = "Segunda saída parcial executada!";
			}

			if (isTerceiraParcial && !_isTerceiraParcial && _terceiraParcialInicio > 0) {
				_isTerceiraParcial = true;
				_trade.Sell(_terceiraParcialVolume, _symbol);
				msg = "Terceira saída parcial executada!";
			}

		}

		if (GetPositionType() == POSITION_TYPE_SELL) {

			isPrimeiraParcial = GetPrice().last <= GetPositionPriceOpen() - _primeiraParcialInicio;
			isSegundaParcial = GetPrice().last <= GetPositionPriceOpen() - _segundaParcialInicio;
			isTerceiraParcial = GetPrice().last <= GetPositionPriceOpen() - _terceiraParcialInicio;

			if (isPrimeiraParcial && !_isPrimeiraParcial && _primeiraParcialInicio > 0) {
				msg = "Primeira saída parcial executada!";
				_isPrimeiraParcial = true;
				_trade.Buy(_primeiraParcialVolume, _symbol);
			}

			if (isSegundaParcial && !_isSegundaParcial && _segundaParcialInicio > 0) {
				msg = "Segunda saída parcial executada!";
				_isSegundaParcial = true;
				_trade.Buy(_segundaParcialVolume, _symbol);
			}

			if (isTerceiraParcial && !_isTerceiraParcial && _terceiraParcialInicio > 0) {
				msg = "Terceira saída parcial executada!";
				_isTerceiraParcial = true;
				_trade.Buy(_terceiraParcialVolume, _symbol);
			}

		}

		if (msg != "") {
			_trade.PositionModify(_symbol, positionLoss, positionGain);
			ShowMessage(msg);
			return true;
		}

		return false;
	}
	
	void ManageDrawParcial(){
	
	   string txtPrimeiraParcial = "Primeira parcial: volume " + (string)_primeiraParcialVolume;
	   string txtSegundaParcial = "Segunda parcial: volume " + (string)_segundaParcialVolume;
	   string txtTerceiraParcial = "Terceira parcial: volume " + (string)_terceiraParcialVolume;
	   
	   string objNamePrimeiraParcial = "PRIMEIRA_PARCIAL";
	   string objNameSegundaParcial = "SEGUNDA_PARCIAL";
	   string objNameTerceiraParcial = "TERCEIRA_PARCIAL";
	
	   ClearDraw(objNamePrimeiraParcial);
      ClearDraw(objNameSegundaParcial);
      ClearDraw(objNameTerceiraParcial);
	
	   if(GetPositionType() == POSITION_TYPE_BUY){
        
         if (!_isPrimeiraParcial && _primeiraParcialInicio > 0) {
	         DrawParcial(objNamePrimeiraParcial, GetPositionPriceOpen() + _primeiraParcialInicio, txtPrimeiraParcial);
	      }
	      
	      if (!_isSegundaParcial && _segundaParcialInicio > 0) {
	         DrawParcial(objNameSegundaParcial, GetPositionPriceOpen() + _segundaParcialInicio, txtSegundaParcial);
	      }
	      
	      if (!_isTerceiraParcial && _terceiraParcialInicio > 0) {
	         DrawParcial(objNameTerceiraParcial, GetPositionPriceOpen() + _terceiraParcialInicio, txtTerceiraParcial);
	      }
	      
	      return;
	      
	   }
	   
	   if(GetPositionType() == POSITION_TYPE_SELL){
         
         if (!_isPrimeiraParcial && _primeiraParcialInicio > 0) {
	         DrawParcial(objNamePrimeiraParcial, GetPositionPriceOpen() - _primeiraParcialInicio, txtPrimeiraParcial);
	      }
	      
	      if (!_isSegundaParcial && _segundaParcialInicio > 0) {
	         DrawParcial(objNameSegundaParcial, GetPositionPriceOpen() - _segundaParcialInicio, txtSegundaParcial);
	      }
	      
	      if (!_isTerceiraParcial && _terceiraParcialInicio > 0) {
	         DrawParcial(objNameTerceiraParcial, GetPositionPriceOpen() - _terceiraParcialInicio, txtTerceiraParcial);
	      }
	      
	      return;
	      
	   }
	
	}
	
	void DrawParcial(string objName, double price, string text){		
	
		ObjectCreate(0, objName, OBJ_ARROW_RIGHT_PRICE, 0, GetPrice().time, price);
		ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDarkMagenta);
		ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, clrBlack);
		ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
		ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
		ObjectSetInteger(0, objName, OBJPROP_BACK, false);
		ObjectSetString(0, objName, OBJPROP_TEXT, text);
	   
	}
	
	void ClearDraw(string objName){
	   ObjectDelete(0, objName);	   
	}
	
   bool SetIsNewCandle() {

		static datetime OldTime;
		datetime NewTime[1];
		bool newBar = false;

		int copied = CopyTime(_symbol, _period, 0, 1, NewTime);

		if (copied > 0 && OldTime != NewTime[0]) {
			newBar = true;
			OldTime = NewTime[0];
		}

		return(newBar);

	}
	
   void ShowInfo() {

		Comment("--------------------------------------" +
			"\n" + _robotName + " " + _robotVersion + " \nFRAMEWORK " + version +
			(_info != "" ? "\n--------------------------------------\n" + _info : "\n--------------------------------------") +
			"\n--------------------------------------" +
			"\nVOLUME " + (string)_volume + " SPREAD " + (string)_spread + " PTS" +
			"\nGAIN " + (string)_stopGain + " PTS LOSS " + (string)_stopLoss + " PTS" +
			(HasPositionOpen() ? "\nVOLUME DA POSICAO ATUAL: " + (GetPositionType() == POSITION_TYPE_SELL ? "-" : "") + (string)GetPositionVolume() : "") +
			"\n--------------------------------------" +
			(_isStopOnLastCandle ? "\nSTOP CANDLE ANTERIOR: SIM\n--------------------------------------" : "") +
			(_isTrailingStop ? "\nTRAIINLING STOP: \nINICIO " + (string)_trailingStopInicio + "PTS VALOR " + (string)_trailingStop + "PTS\n--------------------------------------" : "") +
			(_isBreakEven ? "\nBREAK EVEN: \nINICIO " + (string)_breakEvenInicio + "PTS VALOR " + (string)_breakEven + "PTS\n--------------------------------------" : "") +
			(_isParcial ? "\nPARCIAL: SIM\n--------------------------------------" : "") +
			(_isGerenciamentoFinanceiro ? 
			"\nFINANCEIRO:" +
			"\nGAIN R$ " + DoubleToString(_totalProfitMoney, 2) + " LOSS R$ " + DoubleToString(_totalStopLossMoney, 2) +
			"\nCORRETAGEM: R$ " + DoubleToString(GetTotalCorretagem(), 2) +
			"\nTOTAL R$ " + DoubleToString(GetTotalLucro(), 2) +
			"\nTOTAL LIQUIDO: R$ " + DoubleToString(GetTotalLucroLiquido(), 2) + "\n--------------------------------------" : "")
			);

	}
	
protected:	

   void SetInfo(string info) {
		_info = info;
	}

	int GetPositionType() {
		return (int)PositionGetInteger(POSITION_TYPE);
	}

	double GetPositionGain() {
		return PositionGetDouble(POSITION_TP);
	}

	double GetPositionLoss() {
		return PositionGetDouble(POSITION_SL);
	}

	int GetPositionMagicNumber() {
		return (int)PositionGetInteger(POSITION_MAGIC);
	}

	double GetPositionPriceOpen() {
		return NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), _Digits);
	}

	double GetPositionVolume() {
		return PositionGetDouble(POSITION_VOLUME);
	}

	MqlTick GetPrice() {
		return _lastPrice;
	}

	MqlDateTime GetTimeCurrent() {
		TimeCurrent(_timeCurrent);
		return _timeCurrent;
	}

	bool Validate() {

		bool isValid = true;
		string message = "";
		MqlDateTime time = GetTimeCurrent();

		if (time.hour < GetHoraInicio().hour || time.hour >= GetHoraFim().hour) {
			isValid = false;
		}

		if (time.hour == GetHoraInicio().hour && time.min < GetHoraInicio().min) {
			isValid = false;
		}

		if (time.hour == GetHoraFim().hour && time.min < GetHoraFim().min) {
			isValid = false;
		}

		if (!isValid) {
			message += "\nHorário não permitido!\nSomente entre " + _horaInicioString + " e " + _horaFimString;
		}

		if (isValid) {
			if (time.hour == GetHoraInicioIntervalo().hour) {
				if (time.min >= GetHoraInicioIntervalo().min) {
					isValid = false;
				}
			}

			if (time.hour == GetHoraFimIntervalo().hour) {
				if (time.min <= GetHoraFimIntervalo().min) {
					isValid = false;
				}
			}

			if (!isValid) {
				message += "\nHorário não permitido!\nSomente fora do intervalo de " + _horaInicioIntervaloString + " e " + _horaFimIntervaloString;
			}
		}

		if (_isGerenciamentoFinanceiro) {		   
		
			if ((_isCalcularCorretagemValoresMaximosDiarios ? GetTotalLucroLiquido() : GetTotalLucro()) >= _maximoLucroDiario) {
				isValid = false;
				message += "\nLucro máximo atingido.\nR$ " + (string)GetTotalLucroLiquido();
			}

			if (GetTotalLucro() <= _maximoPrejuizoDiario) {
				isValid = false;
				message += "\nPrejuizo máximo atingido.\nR$ " + (string)GetTotalLucro();
			}
		}

		if (_isParcial && (_primeiraParcialVolume + _segundaParcialVolume + _terceiraParcialVolume) > _volume) {
			isValid = false;
			message += "\nValores de parciais inválidos! Verifique-os.";
		}

		if (HasOrderOpen()) {
			message += "\nExiste ordem pendente aguardando execução.\nAguarde...";
			isValid = false;
		}

		if (!isValid) {
			Comment("--------------------------------------" +
				"\n" + _robotName + " " + _robotVersion + " \nFRAMEWORK " + version +
				"\n--------------------------------------" +
				message +
				"\n--------------------------------------");

			if (message != _lastTextValidate) {
				SendNotification(message);
				SendMail(_robotName, message);
			}

			_lastTextValidate = message;

		}


		return isValid;


	}

	void ShowMessage(string text) {

		if (text != "" && text != _lastText) 
		{
			string message = getRobotName() + " (" + GetSymbol() + ")" + ": " + text;
			
			printf(message);
			
			if (_isNotificacoesApp)
			{
				SendNotification(message);
			}
		}

		_lastText = text;

	}

	void Buy(double entrada, double stopLoss, double stopGain, string comment) {
		_trade.Buy(_volume, _symbol, entrada, stopLoss, stopGain, "ORDEM AUTOMATICA - " + _robotName + " >> " + comment);
		RestartManagePosition();
	}

	void Sell(double entrada, double stopLoss, double stopGain, string comment) {
		_trade.Sell(_volume, _symbol, entrada, stopLoss, stopGain, comment);
		RestartManagePosition();
	}

	void ClosePosition() {
		_trade.PositionClose(_symbol);
	}

	bool HasPositionOpen() {
		return _position.Select(_symbol) && GetPositionMagicNumber() == _trade.RequestMagic();
	}

	bool HasOrderOpen() {

		int orderCount = 0;

		for (int i = 0; i < OrdersTotal(); i++)
		{
			if (OrderSelect(OrderGetTicket(i)) && OrderGetString(ORDER_SYMBOL) == _symbol && OrderGetInteger(ORDER_MAGIC) == _trade.RequestMagic())
			{
				orderCount++;
			}
		}

		return orderCount > 0;

	}	
	
	bool ExecuteBase(){
	
	   if (!SymbolInfoTick(_symbol, _lastPrice)) {
			Alert("Erro ao obter a última cotação de preço:", GetLastError(), "!");
			return false;
		}
		
		_isNewCandle = SetIsNewCandle();
	   
		if (HasPositionOpen()) {
		
			ManagePosition();
			ShowInfo();
			
			return false;
		}

		if (!Validate()) {
			return false;
		}
		
		ShowInfo();
		
		return true;
   		
	}
	
	void ExecuteOnTradeBase(){
	
	   AtualizarQuantidadesStopsAndGains();
	   ShowMessage("Atualização de dados estatísticos de ordens e financeiro. Execução em "+ TimeToString(TimeCurrent()));
	   
	   if(_isParcial){
	      ShowMessage("Atualização de marcações de parciais");
	      ManageDrawParcial();
	   }
	}

public:

	void SetPeriod(ENUM_TIMEFRAMES period) {
		_period = period;
	};

	ENUM_TIMEFRAMES GetPeriod() {
		return _period;
	};

	void SetSymbol(string symbol) {
		_symbol = symbol;
	};

	void SetVolume(int volume) {
		_volume = volume;
	};

	string GetSymbol() {
		return _symbol;
	}

	void SetSpread(double spread) {
		_spread = spread;
	};

	void SetIsClosePosition(bool flag) {
		_isClosePosition = flag;
	}

	double GetSpread() {
		return _spread;
	}

	void SetStopGain(double stopGain) {
		_stopGain = stopGain;
	};

	double GetStopGain() {
		return _stopGain;
	};

	void SetStopLoss(double stopLoss) {
		_stopLoss = stopLoss;
	};

	double GetStopLoss() {
		return _stopLoss;
	};
	
	void SetIsStopOnLastCandle(bool flag) {
		_isStopOnLastCandle = flag;
	}
	
	void SetSpreadStopOnLastCandle(double value){
	   _spreadStopOnLastCandle = value;
	}
	
	double GetSpreadStopOnLastCandle(){
	   return _spreadStopOnLastCandle;
	}	

	void SetNumberMagic(ulong number) {
		_trade.SetExpertMagicNumber(number);
	}

	double GetTotalLucro() {
		return _totalProfitMoney + _totalStopLossMoney;
	}

	double GetTotalLucroLiquido() {
		return GetTotalLucro() - GetTotalCorretagem();
	}

	double GetTotalCorretagem() {
		return (_corretagemValor * _totalOrdensVolume * 2);
	}

	void SetCorretagemValor(double valor) {
		_corretagemValor = valor;
	};

	MqlDateTime GetHoraInicio() {
		return _horaInicio;
	};

	MqlDateTime GetHoraFim() {
		return _horaFim;
	};

	MqlDateTime GetHoraInicioIntervalo() {
		return _horaInicioIntervalo;
	};

	MqlDateTime GetHoraFimIntervalo() {
		return _horaFimIntervalo;
	};

	void SetHoraInicio(string hora) {
		_horaInicioString = hora;
		TimeToStruct(StringToTime("1990.04.02 " + hora), _horaInicio);
	};

	void SetHoraFim(string hora) {
		_horaFimString = hora;
		TimeToStruct(StringToTime("1990.04.02 " + hora), _horaFim);
	};

	void SetHoraInicioIntervalo(string hora) {
		_horaInicioIntervaloString = hora;
		TimeToStruct(StringToTime("1990.04.02 " + hora), _horaInicioIntervalo);
	};

	void SetHoraFimIntervalo(string hora) {
		_horaFimIntervaloString = hora;
		TimeToStruct(StringToTime("1990.04.02 " + hora), _horaFimIntervalo);
	};

	void SetIsCalcularCorretagemValoresMaximosDiarios(bool flag) {
		_isCalcularCorretagemValoresMaximosDiarios = flag;
	}

	void SetMaximoLucroDiario(double valor) {
		_maximoLucroDiario = valor;
	};

	void SetMaximoPrejuizoDiario(double valor) {
		_maximoPrejuizoDiario = valor * -1;
	};

	void SetIsTrailingStop(bool flag) {
		_isTrailingStop = flag;
	}

	void SetTrailingStopInicio(double valor) {
		_trailingStopInicio = valor;
	};

	void SetTrailingStop(double valor) {
		_trailingStop = valor;
	};

	void SetIsBreakEven(bool flag) {
		_isBreakEven = flag;
	}

	void SetBreakEven(double valor) {
		_breakEven = valor;
	}

	void SetBreakEvenInicio(double valor) {
		_breakEvenInicio = valor;
	};

	void SetIsParcial(bool flag) {
		_isParcial = flag;
	}

	void SetPrimeiraParcialInicio(double valor) {
		_primeiraParcialInicio = valor;
	}

	void SetPrimeiraParcialVolume(double valor) {
		_primeiraParcialVolume = valor;
	}

	void SetSegundaParcialInicio(double valor) {
		_segundaParcialInicio = valor;
	}

	void SetSegundaParcialVolume(double valor) {
		_segundaParcialVolume = valor;
	}

	void SetTerceiraParcialInicio(double valor) {
		_terceiraParcialInicio = valor;
	}

	void SetTerceiraParcialVolume(double valor) {
		_terceiraParcialVolume = valor;
	}
	
	void SetIsGerenciamentoFinanceiro(bool flag) {
		_isGerenciamentoFinanceiro = flag;
	}	

	void SetRobotName(string name) {
		_robotName = name;
	}

	string getRobotName() {
		return _robotName;
	}
	
	void SetRobotVersion(string valor) {
		_robotVersion = valor;
	}

	string getRobotVersion() {
		return _robotVersion;
	}
	
	void SetIsNotificacoesApp(bool flag) {
		_isNotificacoesApp = flag;
	}
	
	bool GetIsNewCandle(){
	   return _isNewCandle;
	}

};