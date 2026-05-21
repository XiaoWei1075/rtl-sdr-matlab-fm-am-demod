function SDR_Demod_GUI()
% SDR_Demod_GUI
% 教学级 SDR 非实时解调系统
% 支持 SDR++ / SDR# 录制的双通道 IQ WAV 文件
% 用法：MATLAB 命令窗口输入 SDR_Demod_GUI 后回车

% ------- 初始状态 -------
state.iq        = [];
state.fs        = 2.4e6;
state.fc        = 0;      % IQ录制中心频率，从文件名解析，仅用于频谱轴
state.f_station = 0;      % 目标电台频率，用户手动输入
state.mode      = 'FM';
state.audio     = [];
state.audio_fs  = 48000;
state.filename  = '';

% ------- 主窗口 -------
fig = figure( ...
    'Name',        'MATLAB SDR 非实时解调系统', ...
    'NumberTitle', 'off', ...
    'Position',    [80 60 1100 720], ...
    'Color',       [0.13 0.13 0.18], ...
    'Resize',      'on', ...
    'UserData',    state);

% ------- 颜色 -------
PAN  = [0.18 0.18 0.26];
ACC  = [0.20 0.60 1.00];
GRN  = [0.20 0.80 0.40];
RED  = [0.90 0.35 0.25];
TXT  = [0.95 0.95 0.95];
DARK = [0.08 0.08 0.12];

% ------- 工具栏面板 -------
toolbar = uipanel(fig, ...
    'Position',        [0 0.90 1 0.10], ...
    'BackgroundColor', PAN, ...
    'BorderType',      'none');

% 加载文件
uicontrol(toolbar, ...
    'Style','pushbutton', 'String','📂  加载 IQ 文件', ...
    'Units','normalized', 'Position',[0.01 0.15 0.13 0.70], ...
    'BackgroundColor',ACC, 'ForegroundColor',[1 1 1], ...
    'FontSize',11, 'FontWeight','bold', 'Callback',@cb_load);

% AM 模式按钮
btn_am = uicontrol(toolbar, ...
    'Style','pushbutton', 'String','AM', ...
    'Units','normalized', 'Position',[0.16 0.15 0.07 0.70], ...
    'BackgroundColor',PAN, 'ForegroundColor',TXT, ...
    'FontSize',12, 'FontWeight','bold', 'Callback',@cb_am);

% FM 模式按钮（默认高亮）
btn_fm = uicontrol(toolbar, ...
    'Style','pushbutton', 'String','FM', ...
    'Units','normalized', 'Position',[0.24 0.15 0.07 0.70], ...
    'BackgroundColor',GRN, 'ForegroundColor',[0 0 0], ...
    'FontSize',12, 'FontWeight','bold', 'Callback',@cb_fm);

% 解调按钮
uicontrol(toolbar, ...
    'Style','pushbutton', 'String','解调', ...
    'Units','normalized', 'Position',[0.33 0.15 0.09 0.70], ...
    'BackgroundColor',[0.80 0.55 0.10], 'ForegroundColor',[1 1 1], ...
    'FontSize',11, 'FontWeight','bold', 'Callback',@cb_demod);

% 播放音频按钮
uicontrol(toolbar, ...
    'Style','pushbutton', 'String','▶ 播放', ...
    'Units','normalized', 'Position',[0.44 0.15 0.09 0.70], ...
    'BackgroundColor',[0.20 0.70 0.50], 'ForegroundColor',[1 1 1], ...
    'FontSize',11, 'FontWeight','bold', 'Callback',@cb_play);

% 电台频率标签
uicontrol(toolbar, ...
    'Style','text', 'String','电台(MHz):', ...
    'Units','normalized', 'Position',[0.55 0.20 0.08 0.60], ...
    'BackgroundColor',PAN, 'ForegroundColor',TXT, ...
    'FontSize',10, 'HorizontalAlignment','right');

% 电台频率输入框
edit_fs = uicontrol(toolbar, ...
    'Style','edit', 'String','0', ...
    'Units','normalized', 'Position',[0.64 0.18 0.09 0.64], ...
    'BackgroundColor',[0.22 0.22 0.32], 'ForegroundColor',[1 1 1], ...
    'FontSize',11);

% 确认按钮
uicontrol(toolbar, ...
    'Style','pushbutton', 'String','OK', ...
    'Units','normalized', 'Position',[0.74 0.18 0.05 0.64], ...
    'BackgroundColor',[0.30 0.60 0.30], 'ForegroundColor',[1 1 1], ...
    'FontSize',10, 'FontWeight','bold', 'Callback',@cb_set_fstation);

% 信息标签
lbl_info = uicontrol(toolbar, ...
    'Style','text', 'String','请加载 IQ 文件', ...
    'Units','normalized', 'Position',[0.81 0.08 0.18 0.84], ...
    'BackgroundColor',PAN, 'ForegroundColor',[1 0.85 0.30], ...
    'FontSize',9, 'HorizontalAlignment','left');

% ------- 频谱显示区 -------
ax_spec = axes(fig, ...
    'Position', [0.05 0.42 0.90 0.46], ...
    'Color',DARK, 'XColor',TXT, 'YColor',TXT, ...
    'GridColor',[0.35 0.35 0.45], 'GridAlpha',0.5, ...
    'XGrid','on', 'YGrid','on', 'FontSize',9);
title(ax_spec, '频谱（请先加载文件）', 'Color',TXT, 'FontSize',11);
xlabel(ax_spec, '频率（MHz）', 'Color',TXT);
ylabel(ax_spec, '幅度（dBFS）', 'Color',TXT);

% ------- 解调波形区 -------
ax_wave = axes(fig, ...
    'Position', [0.05 0.06 0.90 0.28], ...
    'Color',DARK, 'XColor',TXT, 'YColor',TXT, ...
    'GridColor',[0.35 0.35 0.45], 'GridAlpha',0.5, ...
    'XGrid','on', 'YGrid','on', 'FontSize',9);
title(ax_wave, '解调波形（请先选择模式并解调）', 'Color',TXT, 'FontSize',11);
xlabel(ax_wave, '时间（ms）', 'Color',TXT);
ylabel(ax_wave, '幅度', 'Color',TXT);

% =====================================================================
% 回调函数
% =====================================================================

    % 加载 IQ 文件
    function cb_load(~, ~)
        [fname, fpath] = uigetfile( ...
            {'*.wav','WAV 文件 (*.wav)';'*.*','所有文件'}, ...
            '选择 SDR IQ 文件');
        if isequal(fname, 0), return; end

        set(lbl_info, 'String', '正在读取…');
        drawnow;

        try
            [raw, fs_file] = audioread(fullfile(fpath, fname));
        catch ME
            errordlg(['读取失败：' ME.message], '错误');
            set(lbl_info, 'String', '读取失败');
            return;
        end

        if size(raw, 2) < 2
            errordlg('需要双通道 I/Q 文件', '格式错误');
            set(lbl_info, 'String', '格式错误');
            return;
        end

        iq = double(raw(:,1)) + 1j*double(raw(:,2));
        fc = parse_fc_from_filename(fname);

        s = get(fig, 'UserData');
        s.iq       = iq;
        s.fs       = fs_file;
        s.fc       = fc;
        s.audio    = [];
        s.filename = fname;
        set(fig, 'UserData', s);

        dur = length(iq) / fs_file;
        set(lbl_info, 'String', sprintf( ...
            '%s\nfs=%.2fMHz  时长=%.1fs\nfc=%.4fMHz', ...
            fname, fs_file/1e6, dur, fc/1e6));

        draw_spectrum(s);
    end

    % 切换 AM
    function cb_am(~, ~)
        s = get(fig, 'UserData');
        s.mode = 'AM';
        set(fig, 'UserData', s);
        set(btn_am, 'BackgroundColor',RED, 'ForegroundColor',[1 1 1]);
        set(btn_fm, 'BackgroundColor',PAN, 'ForegroundColor',TXT);
    end

    % 切换 FM
    function cb_fm(~, ~)
        s = get(fig, 'UserData');
        s.mode = 'FM';
        set(fig, 'UserData', s);
        set(btn_fm, 'BackgroundColor',GRN, 'ForegroundColor',[0 0 0]);
        set(btn_am, 'BackgroundColor',PAN, 'ForegroundColor',TXT);
    end

    % 设定电台频率并刷新频谱
    function cb_set_fstation(~, ~)
        val = str2double(strtrim(char(get(edit_fs, 'String'))));
        if isnan(val)
            msgbox('请输入有效数字（单位 MHz）', '输入错误');
            return;
        end
        s = get(fig, 'UserData');
        s.f_station = val * 1e6;
        set(fig, 'UserData', s);
        set(lbl_info, 'String', sprintf('电台频率已设为 %.4f MHz', val));
        if ~isempty(s.iq)
            draw_spectrum(s);
        end
    end

    % 绘制频谱（供 cb_load 和 cb_set_fstation 调用）
    function draw_spectrum(s)
        iq        = s.iq;
        fs        = s.fs;
        fc        = s.fc;
        f_station = s.f_station;

        % 截取最多 2^20 点
        N_max = 2^20;
        if length(iq) > N_max
            seg = iq(1:N_max);
        else
            seg = iq;
        end
        N  = length(seg);
        X  = fftshift(fft(seg, N));
        Xm = 20*log10(abs(X)/N + eps);

        % 频率轴：以 fc 为中心，转绝对频率 MHz
        f_abs = (linspace(-fs/2, fs/2, N) + fc) / 1e6;

        cla(ax_spec);
        plot(ax_spec, f_abs, Xm, 'Color',[0.30 0.75 1.00], 'LineWidth',0.8);
        set(ax_spec, 'Color',DARK, 'XColor',TXT, 'YColor',TXT, ...
            'GridColor',[0.35 0.35 0.45], 'XGrid','on', 'YGrid','on');
        hold(ax_spec, 'on');

        % fc 参考线（录制中心，橙色虚线）
        if fc ~= 0
            xline(ax_spec, fc/1e6, '--', ...
                'Color',[1 0.6 0.1], 'LineWidth',1.0, ...
                'Label',sprintf('fc=%.3fMHz',fc/1e6), ...
                'LabelColor',[1 0.6 0.1], 'FontSize',8);
        end

        % f_station 参考线（目标电台，绿色实线）
        if f_station ~= 0
            xline(ax_spec, f_station/1e6, '-', ...
                'Color',[0.30 1.00 0.50], 'LineWidth',1.4, ...
                'Label',sprintf('电台=%.3fMHz',f_station/1e6), ...
                'LabelColor',[0.30 1.00 0.50], 'FontSize',8);
        end

        hold(ax_spec, 'off');
        title(ax_spec, sprintf('IQ 频谱  fs=%.2f MHz  N=%d', fs/1e6, N), ...
            'Color',TXT, 'FontSize',11);
        xlabel(ax_spec, '频率（MHz）', 'Color',TXT);
        ylabel(ax_spec, '幅度（dBFS）', 'Color',TXT);
        ylim(ax_spec, [max(Xm)-80, max(Xm)+5]);
    end

    % 解调
    function cb_demod(~, ~)
        s = get(fig, 'UserData');
        if isempty(s.iq)
            msgbox('请先加载 IQ 文件', '提示');
            return;
        end

        set(lbl_info, 'String', '正在解调…');
        drawnow;

        iq        = s.iq;
        fs        = s.fs;
        fc        = s.fc;
        f_station = s.f_station;
        fs_audio  = s.audio_fs;

        switch s.mode

            case 'AM'
                % AM：若电台频率与录制中心有偏差，先频率搬移
                if f_station ~= 0 && abs(f_station - fc) > 1e3
                    f_shift = f_station - fc;
                    t = (0:length(iq)-1)' / fs;
                    iq = iq .* exp(-1j*2*pi*f_shift*t);
                end
                % RF滤波
                iq = lowpass_filter(iq, fs, 4.5e3);
                % 包络检波 m(t) = |I + jQ|
                env = abs(iq);
                env = env - mean(env);
                % 低通 8 kHz（语音带宽）
                env = lowpass_filter(env, fs, 8e3);
                % 降采样
                audio = resample(env, fs_audio, round(fs));
                % RMS自动增益
                rms_val = sqrt(mean(audio.^2));
                target_rms = 0.2;
                if rms_val > 1e-6
                    audio = audio * (target_rms / rms_val);
                end
                % 软限幅
                audio = tanh(2 * audio);
                color_wave = [1.00 0.50 0.20];
                title_str  = 'AM 解调波形（包络检波）';

            case 'FM'
                % FM 三步法：下变频 → 信道滤波 → 鉴频

                % 步骤1：频率搬移，把目标电台移到 0 Hz
                % 若用户未填电台频率，默认 f_station = fc（不搬移）
                if f_station == 0
                    f_station = fc;
                end
                f_shift = f_station - fc;
                t = (0:length(iq)-1)' / fs;
                iq_shift = iq .* exp(-1j*2*pi*f_shift*t);

                % 步骤2：FM 信道低通，截止 100 kHz
                % 只保留目标台，压制相邻台、DC 杂散和 IQ 不平衡
                iq_chan = lowpass_filter(iq_shift, fs, 100e3);

                % 步骤3：相位差分鉴频
                % y[n] = angle( x[n] * conj(x[n-1]) )
                fm = angle(iq_chan(2:end) .* conj(iq_chan(1:end-1)));

                % 去直流
                fm = fm - mean(fm);

                % 音频低通 15 kHz
                fm = lowpass_filter(fm, fs, 15e3);

                % 降采样至 48 kHz
                audio = resample(fm, fs_audio, round(fs));

                % RMS自动增益
                rms_val = sqrt(mean(audio.^2));
                target_rms = 0.2;
                if rms_val > 1e-6
                    audio = audio * (target_rms / rms_val);
                end
                % Soft limiter
                audio = tanh(2 * audio);

                color_wave = [0.30 0.90 0.50];
                title_str  = 'FM 解调波形（下变频 + 相位差分）';

            otherwise
                return;
        end

        % 保存音频到状态
        s.audio = audio;
        set(fig, 'UserData', s);

        % 绘制前 50 ms 波形
        N_show = min(length(audio), round(fs_audio * 0.05));
        t_show = (0:N_show-1) / fs_audio * 1000;

        cla(ax_wave);
        plot(ax_wave, t_show, audio(1:N_show), ...
            'Color',color_wave, 'LineWidth',0.9);
        set(ax_wave, 'Color',DARK, 'XColor',TXT, 'YColor',TXT, ...
            'GridColor',[0.35 0.35 0.45], 'XGrid','on', 'YGrid','on');
        title(ax_wave, title_str, 'Color',TXT, 'FontSize',11);
        xlabel(ax_wave, '时间（ms）', 'Color',TXT);
        ylabel(ax_wave, '归一化幅度', 'Color',TXT);
        ylim(ax_wave, [-1.1 1.1]);

        set(lbl_info, 'String', sprintf( ...
            '解调完成 [%s]\n%.1fs @ %dHz\n点击播放', ...
            s.mode, length(audio)/fs_audio, fs_audio));
    end

    % 播放音频
    function cb_play(~, ~)
        s = get(fig, 'UserData');
        if isempty(s.audio)
            msgbox('请先执行解调', '提示');
            return;
        end
        set(lbl_info, 'String', '播放中…');
        drawnow;
        sound(s.audio, s.audio_fs);
    end

end   % SDR_Demod_GUI 结束

% =====================================================================
% 辅助函数
% =====================================================================

% 低通 FIR 滤波器（Kaiser 窗）
% x     : 输入信号
% fs    : 采样率 Hz
% fc_lp : 截止频率 Hz
function y = lowpass_filter(x, fs, fc_lp)
    Wn = min(fc_lp / (fs/2), 0.99);
    trans_bw = 0.20 * Wn;
    N_ord = min(ceil(6.6 / trans_bw), 512);
    N_ord = N_ord + mod(N_ord, 2);
    b = fir1(N_ord, Wn, 'low', kaiser(N_ord+1, 5));
    y = filtfilt(b, 1, double(x));
end

% 从 SDR++ 文件名解析中心频率
% 格式：baseband_106575000Hz_16-39-27_13-05-2026.wav
function fc = parse_fc_from_filename(fname)
    tok = regexp(fname, '(\d+)Hz', 'tokens');
    if ~isempty(tok)
        fc = str2double(tok{1}{1});
    else
        fc = 0;
    end
end
