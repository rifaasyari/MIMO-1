classdef QPSKRx < matlab.System

% Copyright 2012-2016 The MathWorks, Inc.

    properties (Nontunable)
        DesiredAmplitude = 1/sqrt(2);
        ModulationOrder = 4;
        DownsamplingFactor = 2;
        CoarseCompFrequencyResolution = 50;
        PhaseRecoveryLoopBandwidth = 0.01;
        PhaseRecoveryDampingFactor = 1;
        TimingRecoveryDampingFactor = 1;
        TimingRecoveryLoopBandwidth = 0.01;
        TimingErrorDetectorGain = 5.4;
        PostFilterOversampling = 2;
        FrameSize = 100;
        BarkerLength = 13;
        MessageLength = 105;
        SampleRate = 200000;
        DataLength = 174;
        ReceiverFilterCoefficients = 1;
        DescramblerBase = 2;
        DescramblerPolynomial = [1 1 1 0 1];
        DescramblerInitialConditions = [0 0 0 0];
        PrintOption = false;
        
        pLen = 8;
        NumRxAntenna = 2;
    end
    
    properties (Access = private)
        pAGC
        pRxFilter
        pCoarseFreqEstimator
        pCoarseFreqCompensator
        pFineFreqCompensator
        pTimingRec
        pPrbDet
        pFrameSync
        pDataDecod
        pBER
        
        pMIMODecoder
     end
    
    properties (Access = private, Constant)
        pUpdatePeriod = 4 % Defines the size of vector that will be processed in AGC system object
        pBarkerCode = [+1; +1; +1; +1; +1; -1; -1; +1; +1; -1; +1; -1; +1]; % Bipolar Barker Code        
        pModulatedHeader = sqrt(2)/2 * (-1-1i) * QPSKRx.pBarkerCode;
    end
    
    methods
        function obj = QPSKRx(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    
    methods (Access = protected)
        function setupImpl(obj, ~, ~)
            obj.pAGC = comm.AGC;

            obj.pRxFilter = dsp.FIRDecimator( ...
                'Numerator', obj.ReceiverFilterCoefficients, ...
                'DecimationFactor', obj.DownsamplingFactor);
            
            obj.pCoarseFreqEstimator = comm.PSKCoarseFrequencyEstimator( ...
                'ModulationOrder',     obj.ModulationOrder, ...
                'Algorithm',           'FFT-based', ...
                'FrequencyResolution', obj.CoarseCompFrequencyResolution, ...
                'SampleRate',          obj.SampleRate);

            obj.pCoarseFreqCompensator = comm.PhaseFrequencyOffset( ...
                'PhaseOffset',           0, ...
                'FrequencyOffsetSource', 'Input port', ...
                'SampleRate',            obj.SampleRate);
            
            obj.pFineFreqCompensator = comm.CarrierSynchronizer( ...
                'Modulation',              'QPSK', ...
                'ModulationPhaseOffset',   'Auto', ...
                'SamplesPerSymbol',        obj.PostFilterOversampling, ...
                'DampingFactor',           obj.PhaseRecoveryDampingFactor, ...
                'NormalizedLoopBandwidth', obj.PhaseRecoveryLoopBandwidth);
            
            obj.pTimingRec = comm.SymbolSynchronizer( ...
                'TimingErrorDetector',     'Zero-Crossing (decision-directed)', ...
                'SamplesPerSymbol',        obj.PostFilterOversampling, ...
                'DampingFactor',           obj.TimingRecoveryDampingFactor, ...
                'NormalizedLoopBandwidth', obj.TimingRecoveryLoopBandwidth, ...
                'DetectorGain',            obj.TimingErrorDetectorGain);  
            
            obj.pPrbDet = comm.PreambleDetector(obj.pModulatedHeader, ...
                'Input',     'Symbol', ...
                'Threshold', 8);
            
            obj.pFrameSync = FrameSynchronizer( ...
                'OutputFrameLength',      obj.FrameSize, ...
                'PreambleLength', length(obj.pModulatedHeader));
            
            obj.pDataDecod = QPSKDecoder('FrameSize', obj.FrameSize, ...
                'BarkerLength', obj.BarkerLength, ...
                'ModulationOrder', obj.ModulationOrder, ...
                'DataLength', obj.DataLength, ...
                'MessageLength', obj.MessageLength, ...
                'DescramblerBase', obj.DescramblerBase, ...
                'DescramblerPolynomial', obj.DescramblerPolynomial, ...
                'DescramblerInitialConditions', obj.DescramblerInitialConditions, ...
                'PrintOption', obj.PrintOption);
            
            obj.pMIMODecoder = comm.OSTBCCombiner;
            obj.pMIMODecoder.NumReceiveAntennas = obj.NumRxAntenna;
        end
                
        function [RCRxSignal, fineCompSignal, timingRecBuffer,BER] = stepImpl(obj, bufferSignal, H)
            
            MIMOsignal = obj.pMIMODecoder(bufferSignal(obj.pLen+1:end,:),squeeze(H(obj.pLen+1:end,:,:,:)));
            RCRxSignal = MIMOsignal;
            fineCompSignal = MIMOsignal;
            timingRecBuffer = MIMOsignal;
            
            obj.pBER = obj.pDataDecod(MIMOsignal);

            BER = obj.pBER;
        end
        
        function resetImpl(obj)
            obj.pBER = zeros(3, 1);
            reset(obj.pAGC);
            reset(obj.pRxFilter);
            reset(obj.pCoarseFreqEstimator);
            reset(obj.pCoarseFreqCompensator);
            reset(obj.pFineFreqCompensator);
            reset(obj.pTimingRec);
            reset(obj.pPrbDet);
            reset(obj.pFrameSync);
            reset(obj.pDataDecod);
        end
        
        function releaseImpl(obj)
            release(obj.pAGC);
            release(obj.pRxFilter);
            release(obj.pCoarseFreqEstimator);
            release(obj.pCoarseFreqCompensator);
            release(obj.pFineFreqCompensator);
            release(obj.pTimingRec);
            release(obj.pPrbDet);
            release(obj.pFrameSync);
            release(obj.pDataDecod);            
        end
        
        function N = getNumOutputsImpl(~)
            N = 4;
        end
    end
end

