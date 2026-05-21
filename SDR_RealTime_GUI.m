function SDR_RealTime_GUI()
% SDR_RealTime_GUI
% 教学级 RTL-SDR 实时 AM/FM 解调系统（性能优化版）
% 硬件：RTL-SDR Blog V4（或兼容设备）
% 依赖：Communications Toolbox、DSP System Toolbox、Audio Toolbox（可选）
%
% 性能优化要点（针对 MATLAB 实时处理瓶颈）：
%   1. 采样率 FM=240kHz / AM=96kHz（远低于 2.4MHz，CPU 负荷骤降）
%   2. SamplesPerFrame=8192（减少函数调用频率）
%   3. 滤波器仅在启动时设计一次，运行时只调用 filter()
%   4. 用 filter() + 直接抽取取代 resample()（快 5~10 倍）
%   5. GUI 每 10 帧刷新一次，配合 drawnow limitrate

% ------- 初始状态 -------
state.rx          = [];       % comm.SDRRTLReceiver
state.bbw         = [];       % comm.BasebandFileWriter
state.adw         = [];       % audioDeviceWriter
state.tmr         = [];       % timer
state.running     = false;
state.recording   = false;
state.mode        = 'FM';
state.fc          = 105.6e6;
state.gain        = 25;
state.fs          = 960e3;    % 增大采样率覆盖更宽频谱 (960kHz)
state.frame_count = 0;
% 预设计滤波器（启动时填充）
state.b_chan      = [];       % 信道低通 FIR 系数
state.zi_chan     = [];       % 信道滤波器状态（含复数 IQ）
state.audio_decim = [];       % 多相抽取滤波器对象 (dsp.FIRDecimator)
state.decim_n     = 20;       % 抽取倍数 20（960kHz→48kHz）
state.agc_gain    = 1.0;      % 跨帧持续的自动增益(AGC)
state.zi_dc       = 0;        % 音频去除直流分量的滤波器状态
state.f_hw        = 105.6e6;  % 硬件实际调谐频率
state.f_shift     = 0;        % 数字频移量
state.nco_phase   = 0;        % NCO连续相位
state.iq_last     = 0;        % FM相位差分鉴频跨帧记忆点
state.h_spec      = [];
state.h_fc_line   = [];
state.h_fc_text   = [];
state.h_wave      = [];

% ------- 颜色常量 -------
PAN  = [0.15 0.15 0.22];
GRN  = [0.20 0.78 0.38];
RED  = [0.88 0.30 0.22];
ORG  = [0.82 0.50 0.10];
TXT  = [0.95 0.95 0.95];
DARK = [0.07 0.07 0.11];
SBAR = [0.10 0.10 0.16];

% ------- 主窗口 -------
fig = figure( ...
    'Name',            'MATLAB SDR 实时解调系统', ...
    'NumberTitle',     'off', ...
    'Position',        [60 50 1120 760], ...
    'Color',           PAN, ...
    'Resize',          'on', ...
    'CloseRequestFcn', @fig_close, ...
    'UserData',        state);

% ------- 工具栏面板 -------
toolbar = uipanel(fig, ...
    'Position',        [0 0.88 1 0.12], ...
    'BackgroundColor', PAN, ...
    'BorderType',      'none');

uicontrol(toolbar, 'Style','text', 'String','中心频率(MHz):', ...
    'Units','normalized', 'Position',[0.01 0.25 0.10 0.50], ...
    'BackgroundColor',PAN, 'ForegroundColor',TXT, ...
    'FontSize',10, 'HorizontalAlignment','right');

edit_fc = uicontrol(toolbar, 'Style','edit', 'String','105.6', ...
    'Units','normalized', 'Position',[0.12 0.18 0.09 0.64], ...
    'BackgroundColor',[0.20 0.20 0.30], 'ForegroundColor',[1 1 1], ...
    'FontSize',11);

uicontrol(toolbar, 'Style','pushbutton', 'String','调谐', ...
    'Units','normalized', 'Position',[0.22 0.18 0.05 0.64], ...
    'BackgroundColor',[0.28 0.55 0.28], 'ForegroundColor',[1 1 1], ...
    'FontSize',10, 'FontWeight','bold', 'Callback',@cb_tune);

btn_am = uicontrol(toolbar, 'Style','pushbutton', 'String','AM', ...
    'Units','normalized', 'Position',[0.29 0.18 0.06 0.64], ...
    'BackgroundColor',PAN, 'ForegroundColor',TXT, ...
    'FontSize',12, 'FontWeight','bold', 'Callback',@cb_am);

btn_fm = uicontrol(toolbar, 'Style','pushbutton', 'String','FM', ...
    'Units','normalized', 'Position',[0.36 0.18 0.06 0.64], ...
    'BackgroundColor',GRN, 'ForegroundColor',[0 0 0], ...
    'FontSize',12, 'FontWeight','bold', 'Callback',@cb_fm);

uicontrol(toolbar, 'Style','text', 'String','增益(dB):', ...
    'Units','normalized', 'Position',[0.44 0.25 0.06 0.50], ...
    'BackgroundColor',PAN, 'ForegroundColor',TXT, ...
    'FontSize',10, 'HorizontalAlignment','right');

edit_gain = uicontrol(toolbar, 'Style','edit', 'String','25', ...
    'Units','normalized', 'Position',[0.51 0.18 0.05 0.64], ...
    'BackgroundColor',[0.20 0.20 0.30], 'ForegroundColor',[1 1 1], ...
    'FontSize',11);

btn_start = uicontrol(toolbar, 'Style','pushbutton', 'String','▶ 开始', ...
    'Units','normalized', 'Position',[0.58 0.18 0.09 0.64], ...
    'BackgroundColor',GRN, 'ForegroundColor',[0 0 0], ...
    'FontSize',11, 'FontWeight','bold', 'Callback',@cb_start);

btn_stop = uicontrol(toolbar, 'Style','pushbutton', 'String','■ 停止', ...
    'Units','normalized', 'Position',[0.68 0.18 0.09 0.64], ...
    'BackgroundColor',RED, 'ForegroundColor',[1 1 1], ...
    'FontSize',11, 'FontWeight','bold', 'Callback',@cb_stop, 'Enable','off');

btn_rec = uicontrol(toolbar, 'Style','pushbutton', 'String','⏺ 录制', ...
    'Units','normalized', 'Position',[0.79 0.18 0.09 0.64], ...
    'BackgroundColor',ORG, 'ForegroundColor',[1 1 1], ...
    'FontSize',11, 'FontWeight','bold', 'Callback',@cb_record);

lbl_status = uicontrol(toolbar, 'Style','text', ...
    'String','就绪 | 请点击 ▶ 开始', ...
    'Units','normalized', 'Position',[0.90 0.08 0.09 0.84], ...
    'BackgroundColor',PAN, 'ForegroundColor',[1 0.85 0.30], ...
    'FontSize',9, 'HorizontalAlignment','left');

% ------- 频谱显示区 -------
ax_spec = axes(fig, ...
    'Position', [0.05 0.47 0.90 0.39], ...
    'Color',DARK, 'XColor',TXT, 'YColor',TXT, ...
    'GridColor',[0.35 0.35 0.45], 'GridAlpha',0.5, ...
    'XGrid','on', 'YGrid','on', 'FontSize',9);
title(ax_spec, '实时频谱（等待数据）', 'Color',TXT, 'FontSize',11);
xlabel(ax_spec, '频率（MHz）', 'Color',TXT);
ylabel(ax_spec, '幅度（dBFS）', 'Color',TXT);
disableDefaultInteractivity(ax_spec);
axtoolbar(ax_spec, 'visible', 'off');

% ------- 解调波形区 -------
ax_wave = axes(fig, ...
    'Position', [0.05 0.09 0.90 0.30], ...
    'Color',DARK, 'XColor',TXT, 'YColor',TXT, ...
    'GridColor',[0.35 0.35 0.45], 'GridAlpha',0.5, ...
    'XGrid','on', 'YGrid','on', 'FontSize',9);
title(ax_wave, '解调音频波形（等待数据）', 'Color',TXT, 'FontSize',11);
xlabel(ax_wave, '时间（ms）', 'Color',TXT);
ylabel(ax_wave, '归一化幅度', 'Color',TXT);
disableDefaultInteractivity(ax_wave);
axtoolbar(ax_wave, 'visible', 'off');

% ------- 底部状态栏 -------
uipanel(fig, 'Position',[0 0 1 0.07], ...
    'BackgroundColor',SBAR, 'BorderType','none');
lbl_bottom = uicontrol(fig, 'Style','text', ...
    'String','RTL-SDR 实时解调系统 | 请先连接硬件', ...
    'Units','normalized', 'Position',[0.01 0.005 0.98 0.055], ...
    'BackgroundColor',SBAR, 'ForegroundColor',[0.65 0.65 0.78], ...
    'FontSize',9, 'HorizontalAlignment','left');

% ------- Timer（30ms 周期，小于 32000帧@960kHz=33.3ms） -------
tmr = timer( ...
    'Period',        0.030, ...
    'ExecutionMode', 'fixedRate', ...
    'TimerFcn',      @timer_cb, ...
    'ErrorFcn',      @timer_err);

s = get(fig, 'UserData');
s.h_spec = line(ax_spec, nan, nan, 'Color',[0.25 0.70 1.00], 'LineWidth',0.7);
s.h_fc_line = line(ax_spec, [nan nan], [nan nan], 'LineStyle','--', ...
    'Color',[1.0 0.6 0.1], 'LineWidth',0.9);
s.h_fc_text = text(ax_spec, nan, nan, '', 'Color',[1.0 0.6 0.1], ...
    'FontSize',8, 'HorizontalAlignment','left', 'VerticalAlignment','bottom');
s.h_wave = line(ax_wave, nan, nan, 'Color',[0.22 0.88 0.42], 'LineWidth',0.8);
s.tmr = tmr;
set(fig, 'UserData', s);

% =====================================================================
% 回调函数
% =====================================================================

    function cb_start(~, ~)
        s = get(fig, 'UserData');
        if s.running, return; end

        fc_val   = str2double(strtrim(char(get(edit_fc,   'String')))) * 1e6;
        gain_val = str2double(strtrim(char(get(edit_gain, 'String'))));
        if isnan(fc_val) || isnan(gain_val)
            msgbox('请检查频率和增益输入', '输入错误');
            return;
        end

        s.fc   = fc_val;
        s.gain = gain_val;
        s.fs   = 960e3;
        s.decim_n = 20;

        s = apply_hardware_tuning(s);

        set(lbl_status, 'String', '初始化SDR…');
        drawnow;

        % 创建 SDR 接收机
        % SamplesPerFrame=32000：确保是抽取倍数(20)的整数倍，避免多相抽取器卡顿
        try
            s.rx = comm.SDRRTLReceiver( ...
                'CenterFrequency',  s.f_hw, ...
                'SampleRate',       s.fs, ...
                'EnableTunerAGC',   false, ...
                'TunerGain',        s.gain, ...
                'OutputDataType',   'double', ...
                'SamplesPerFrame',  32000);
            step(s.rx);    % 丢弃第一帧（硬件预热）
        catch ME
            errordlg(['SDR初始化失败：' ME.message], 'SDR错误');
            if ~isempty(s.rx)
                try; release(s.rx); catch; end
                s.rx = [];
            end
            set(lbl_status, 'String', '初始化失败');
            set(fig, 'UserData', s);
            return;
        end

        % 预设计滤波器（仅此一次，避免每帧重复设计）
        [s.b_chan, s.zi_chan, s.audio_decim] = design_filters(s.mode, s.fs, s.decim_n);
        s.agc_gain = 1.0;
        s.zi_dc    = 0;
        s.nco_phase = 0;
        s.iq_last  = 0;

        % 音频输出
        try
            s.adw = audioDeviceWriter('SampleRate', 48000, 'BufferSize', 8192);
        catch
            s.adw = [];
        end

        s.running     = true;
        s.frame_count = 0;
        set(fig, 'UserData', s);
        set(btn_start, 'Enable','off');
        set(btn_stop,  'Enable','on');
        set(lbl_status, 'String', '运行中…');
        start(tmr);
    end

    function cb_stop(~, ~)
        s = get(fig, 'UserData');
        if ~s.running, return; end
        stop(tmr);
        if s.recording
            safe_release(s.bbw);
            s.bbw = [];
            s.recording = false;
            set(btn_rec, 'BackgroundColor',ORG, 'String','⏺ 录制');
        end
        safe_release(s.rx);
        safe_release(s.adw);
        safe_release(s.audio_decim);
        s.rx      = [];
        s.adw     = [];
        s.running = false;
        set(fig, 'UserData', s);
        set(btn_start, 'Enable','on');
        set(btn_stop,  'Enable','off');
        set(lbl_status, 'String', sprintf('已停止 | 共 %d 帧', s.frame_count));
    end

    function cb_record(~, ~)
        s = get(fig, 'UserData');
        if ~s.running
            msgbox('请先点击"开始"', '提示');
            return;
        end
        if ~s.recording
            fname = sprintf('iq_%s_%.3fMHz_%s.bb', ...
                s.mode, s.fc/1e6, datestr(now, 'HHMMSS'));
            try
                s.bbw = comm.BasebandFileWriter( ...
                    'Filename',        fname, ...
                    'SampleRate',      s.fs, ...
                    'CenterFrequency', s.fc);
                s.recording = true;
                set(btn_rec, 'BackgroundColor',[0.80 0.12 0.12], 'String','⏹ 停录');
                set(lbl_status, 'String', ['● REC: ' fname]);
            catch ME
                errordlg(['录制启动失败：' ME.message], '录制错误');
            end
        else
            safe_release(s.bbw);
            s.bbw       = [];
            s.recording = false;
            set(btn_rec, 'BackgroundColor',ORG, 'String','⏺ 录制');
            set(lbl_status, 'String', '录制已停止');
        end
        set(fig, 'UserData', s);
    end

    function cb_tune(~, ~)
        s = get(fig, 'UserData');
        fc_val = str2double(strtrim(char(get(edit_fc, 'String')))) * 1e6;
        if isnan(fc_val)
            msgbox('请输入有效频率（单位 MHz）', '输入错误');
            return;
        end
        s.fc = fc_val;
        s = apply_hardware_tuning(s);
        set(fig, 'UserData', s);
        set(lbl_status, 'String', sprintf('已调谐至 %.4f MHz', fc_val/1e6));
    end

    function cb_am(~, ~)
        s = get(fig, 'UserData');
        s.mode = 'AM';

        % 标定AM常用默认频率(如中波 1.008MHz)并提高增益(短波/中波需要更高增益)
        s.fc = 1.008e6;
        s.gain = 40;
        set(edit_fc, 'String', '1.008');
        set(edit_gain, 'String', '40');

        s = apply_hardware_tuning(s);
        if s.running && ~isempty(s.rx)
            try
                s.rx.TunerGain = s.gain;
            catch
            end
        end

        set(fig, 'UserData', s);
        set(btn_am, 'BackgroundColor',RED, 'ForegroundColor',[1 1 1]);
        set(btn_fm, 'BackgroundColor',PAN, 'ForegroundColor',TXT);
        if s.running
            set(lbl_status, 'String', 'AM（已切换频率至1.008MHz）');
        end
    end

    function cb_fm(~, ~)
        s = get(fig, 'UserData');
        s.mode = 'FM';

        % 标定FM常用默认频率(如 105.6MHz)和增益
        s.fc = 105.6e6;
        s.gain = 25;
        set(edit_fc, 'String', '105.6');
        set(edit_gain, 'String', '25');

        s = apply_hardware_tuning(s);
        if s.running && ~isempty(s.rx)
            try
                s.rx.TunerGain = s.gain;
            catch
            end
        end

        set(fig, 'UserData', s);
        set(btn_fm, 'BackgroundColor',GRN, 'ForegroundColor',[0 0 0]);
        set(btn_am, 'BackgroundColor',PAN, 'ForegroundColor',TXT);
        if s.running
            set(lbl_status, 'String', 'FM（已切换频率至105.6MHz）');
        end
    end

    function fig_close(~, ~)
        s = get(fig, 'UserData');
        if ~isempty(s.tmr) && isvalid(s.tmr)
            if strcmp(s.tmr.Running, 'on'), stop(s.tmr); end
            delete(s.tmr);
        end
        safe_release(s.rx);
        safe_release(s.adw);
        safe_release(s.audio_decim);
        safe_release(s.bbw);
        delete(fig);
    end

    % Timer 回调：核心处理循环
    % 每 35ms 执行一次（对应 8192 点 @ 240kHz = 34ms）
    % 优化点：
    %   - filter() 而非 filtfilt()（无需双向，节省一半计算量）
    %   - filter 状态（zi）跨帧持续，确保无缝拼接、无边界噪声
    %   - 直接下标抽取取代 resample()
    %   - 每 10 帧才刷新 GUI
    function timer_cb(~, ~)
        s = get(fig, 'UserData');
        if ~s.running || isempty(s.rx), return; end

        try
            [iq, ~, overflow] = step(s.rx);
        catch
            return;
        end

        % 数字下变频：将偏置调谐偏移补回，使得电台频率回到基带 0Hz
        if s.f_shift ~= 0
            t = (0 : length(iq)-1)' / s.fs;
            nco = exp(1i * (2 * pi * s.f_shift * t + s.nco_phase));
            s.nco_phase = mod(s.nco_phase + 2 * pi * s.f_shift * length(iq) / s.fs, 2*pi);
            iq = iq .* nco;
        end

        % 录制 IQ
        if s.recording && ~isempty(s.bbw)
            try; step(s.bbw, iq); catch; end
        end

        % 解调（传入并更新滤波器状态，保证帧间连续）
        switch s.mode
            case 'FM'
                [audio, s.zi_chan, s.agc_gain, s.zi_dc, s.iq_last] = ...
                    demod_fm(iq, s.b_chan, s.zi_chan, s.audio_decim, s.agc_gain, s.zi_dc, s.iq_last);
            case 'AM'
                [audio, s.zi_chan, s.agc_gain, s.zi_dc] = ...
                    demod_am(iq, s.b_chan, s.zi_chan, s.audio_decim, s.agc_gain, s.zi_dc);
            otherwise
                audio = zeros(round(length(iq)/s.decim_n), 1);
                s.zi_chan  = [];
                s.agc_gain = 1.0;
                s.zi_dc    = 0;
                s.iq_last  = 0;
        end

        % 音频播放
        if ~isempty(s.adw)
            try; s.adw(audio); catch; end
        end

        s.frame_count = s.frame_count + 1;

        % 每 10 帧刷新一次 GUI（≈350ms），drawnow limitrate 防阻塞
        if mod(s.frame_count, 10) == 0
            do_update_spectrum(iq, s.fs, s.fc);
            do_update_waveform(audio, s.mode);

            rec_tag = ''; if s.recording, rec_tag = '  ⏺REC'; end
            ov_tag  = ''; if overflow,    ov_tag  = '  ⚠OVF'; end
            set(lbl_status, 'String', ...
                sprintf('%s | %.3fMHz%s%s', s.mode, s.fc/1e6, rec_tag, ov_tag));
            set(lbl_bottom, 'String', sprintf( ...
                'RTL-SDR | %s | fc=%.4f MHz | fs=%.0f kHz | 帧=%d | 音频=48kHz | decimate=%d%s', ...
                s.mode, s.fc/1e6, s.fs/1e3, s.frame_count, s.decim_n, ov_tag));
            drawnow limitrate;
        end

        set(fig, 'UserData', s);
    end

    function timer_err(~, event)
        disp(['[Timer 错误] ' event.Data.message]);
        set(lbl_status, 'String', 'Timer错误，请重启');
    end

    % 频谱更新（在 timer_cb 中调用）
    % FFT 点数限制在 4096 以内，减少绘图数据量
    function do_update_spectrum(iq, fs, fc)
        s = get(fig, 'UserData');
        N_fft = min(length(iq), 4096);
        X     = fftshift(fft(iq(1:N_fft), N_fft));
        Xm    = 20*log10(abs(X)/N_fft + eps);
        f     = (linspace(-fs/2, fs/2, N_fft) + fc) / 1e6;

        % 固定频谱的纵向显示范围，避免底噪抖动引起的画面自动缩放
        y_lim = [-120, 0]; 

        set(s.h_spec, 'XData', f, 'YData', Xm);
        set(ax_spec, 'YLim', y_lim);
        set(s.h_fc_line, 'XData', [fc fc]/1e6, 'YData', y_lim);
        set(s.h_fc_text, 'Position', [fc/1e6, y_lim(2), 0], ...
            'String', sprintf('%.4fMHz', fc/1e6));
        title(ax_spec, sprintf('实时频谱  fc=%.4f MHz  fs=%.0f kHz', fc/1e6, fs/1e3), ...
            'Color',TXT, 'FontSize',10);
    end

    % 波形更新（在 timer_cb 中调用）
    % 时间轴直接用 (1:N)/48000，无需 persistent 变量
    function do_update_waveform(audio, mode)
        if isempty(audio), return; end
        s = get(fig, 'UserData');
        col = [0.22 0.88 0.42];
        if strcmp(mode, 'AM'), col = [1.00 0.48 0.18]; end
        N = length(audio);
        t = (1:N) / 48000 * 1000;   % ms
        set(s.h_wave, 'XData', t, 'YData', audio, 'Color', col);
        title(ax_wave, [mode ' 解调音频波形  （48 kHz）'], 'Color',TXT, 'FontSize',10);
        xlabel(ax_wave, '时间（ms）', 'Color',TXT);
        ylabel(ax_wave, '归一化幅度', 'Color',TXT);
        ylim(ax_wave, [-1.1 1.1]);
    end

    function s = apply_hardware_tuning(s)
        if strcmp(s.mode, 'AM')
            if abs(s.fc - 740e3) < abs(s.fc - 1065e3)
                s.f_hw = 740e3;
            else
                s.f_hw = 1065e3;
            end
            s.f_shift = s.f_hw - s.fc;
        else
            s.f_hw = s.fc;
            s.f_shift = 0;
        end
        if s.running && ~isempty(s.rx)
            try
                s.rx.CenterFrequency = s.f_hw;
            catch
            end
        end
    end

    function safe_release(obj)
        if ~isempty(obj)
            try; release(obj); catch; end
        end
    end

end   % SDR_RealTime_GUI 结束

% =====================================================================
% DSP 辅助函数（主函数外，不访问 GUI 句柄）
% =====================================================================

% 开始时预设计所有滤波器并返回抽取器对象
function [b_chan, zi_chan, audio_decim] = design_filters(mode, fs, decim_n)
    if strcmp(mode, 'FM')
        % 信道低通：75 kHz（FM 广播单台带宽约 ±75kHz）
        b_chan  = fir1(128, 75e3/(fs/2),  'low', kaiser(129, 6));
        % 音频低通：15 kHz（FM 音频带宽，同时作抗混叠）
        b_audio = fir1(128, 15e3/(fs/2),  'low', kaiser(129, 6));
    else
        % AM 信道低通：10 kHz（AM 单边带带宽约 10kHz）
        b_chan  = fir1(128, 10e3/(fs/2),  'low', kaiser(129, 6));
        % AM 音频低通：8 kHz（AM 话音带宽）
        b_audio = fir1(128,  8e3/(fs/2),  'low', kaiser(129, 6));
    end
    % zi_chan 为复数（IQ 信号）
    zi_chan  = complex(zeros(length(b_chan)-1,  1));
    % 基于 DSP System Toolbox 的多相抽取器
    audio_decim = dsp.FIRDecimator(decim_n, b_audio);
end

% FM 实时解调
% 输入：iq      复数 IQ 帧（已调谐至电台中心频率）
%       b_chan  信道 FIR 系数
%       zi_chan 信道滤波器状态（跨帧保持，消除边界毛刺）
%       audio_decim dsp.FIRDecimator实例（多相混叠抽取滤波一体化）
%       agc_gain 当前帧的自动增益乘数
%       zi_dc 去直流滤波器状态
%       iq_last 上一帧运算留下的最后一个复数样点
% 输出：audio   归一化单声道 48kHz
%       zi_chan_out / agc_gain_out / zi_dc_out / iq_last_out 更新后的状态
%
% 信号流：
%   iq(960kHz) → 信道LPF(75kHz) → 相位差分鉴频 → 多相抽取×20 → 连续去直流 → 48kHz
function [audio, zi_chan_out, agc_gain_out, zi_dc_out, iq_last_out] = ...
        demod_fm(iq, b_chan, zi_chan, audio_decim, agc_gain, zi_dc, iq_last)
    % 信道低通（含 IQ 不平衡与 DC 压制）
    [iq_f, zi_chan_out] = filter(b_chan, 1, iq, zi_chan);

    % 利用跨帧存储的最后一个点进行无缝差分，彻底避免塞入零导致的 30Hz 咔哒声
    delayed_iq_f = [iq_last; iq_f(1:end-1)];
    fm = angle(iq_f .* conj(delayed_iq_f));
    iq_last_out = iq_f(end);

    % 一步完成抗混叠低通和抽取 (速度极快)
    audio = audio_decim(fm);

    % IIR 连续去直流（去除鉴频后的残余频偏）
    [audio, zi_dc_out] = filter([1 -1], [1 -0.995], audio, zi_dc);

    % RMS 自动增益控制 (AGC)
    rms_val = sqrt(mean(audio.^2)) + 1e-5;
    target_rms = 0.15; % 目标均方根幅度

    % 平滑更新增益 (alpha = 0.1)
    agc_gain_out = 0.9 * agc_gain + 0.1 * (target_rms / rms_val);
    agc_gain_out = max(0.1, min(agc_gain_out, 30));

    % 插值平滑应用增益，消除块增益跳变导致的规律性爆音
    gain_vec = linspace(agc_gain, agc_gain_out, length(audio)).';
    audio = audio .* gain_vec;
    audio = tanh(audio); % 软限幅
end

% AM 实时解调
% 信号流：
%   iq(已混至基带) → 信道LPF(10kHz) → 包络检波 → 多相抽取×20 → 连续去直流 → 48kHz
function [audio, zi_chan_out, agc_gain_out, zi_dc_out] = ...
        demod_am(iq, b_chan, zi_chan, audio_decim, agc_gain, zi_dc)

    % 信道低通（压制邻道噪声）
    [iq_f, zi_chan_out] = filter(b_chan, 1, iq, zi_chan);

    % 包络检波：m(t) = |I(t) + jQ(t)|
    env = abs(iq_f);

    % 一步完成抗混叠低通和抽取 (速度极快)
    audio = audio_decim(env);

    % IIR 连续去直流（去除包络直流底座，取代分块 mean() 避免 30Hz 咔哒噪声淹没微弱信号）
    [audio, zi_dc_out] = filter([1 -1], [1 -0.995], audio, zi_dc);

    % RMS 自动增益控制 (AGC)
    rms_val = sqrt(mean(audio.^2)) + 1e-5;
    target_rms = 0.3; % 目标均方根幅度

    % 平滑更新增益 (alpha = 0.1)
    agc_gain_out = 0.9 * agc_gain + 0.1 * (target_rms / rms_val);
    agc_gain_out = max(0.1, min(agc_gain_out, 50));

    % 插值平滑应用增益，消除块增益跳变导致的规律性爆音
    gain_vec = linspace(agc_gain, agc_gain_out, length(audio)).';
    audio = audio .* gain_vec;
    audio = tanh(audio); % 软限幅
end
