function varargout = vis(varargin)
% VIS MATLAB code for vis.fig
%      VIS, by itself, creates a new VIS or raises the existing
%      singleton*.
%
%      H = VIS returns the handle to a new VIS or the handle to
%      the existing singleton*.
%
%      VIS('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in VIS.M with the given input arguments.
%
%      VIS('Property','Value',...) creates a new VIS or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before vis_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to vis_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help vis

% Last Modified by GUIDE v2.5 12-Jun-2025 05:42:35

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @vis_OpeningFcn, ...
                   'gui_OutputFcn',  @vis_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before vis is made visible.
function vis_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to vis (see VARARGIN)

% Choose default command line output for vis
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);
global G
% UIWAIT makes vis wait for user response (see UIRESUME)
% uiwait(handles.figure1);
G.n=100;
G.

% --- Outputs from this function are returned to the command line.
function varargout = vis_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% --- Executes on slider movement.
function ph_slider_Callback(hObject, eventdata, handles)
% hObject    handle to ph_slider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'Value') returns position of slider
%        get(hObject,'Min') and get(hObject,'Max') to determine range of slider


% --- Executes on slider movement.
function amp_slider_Callback(hObject, eventdata, handles)
% hObject    handle to amp_slider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'Value') returns position of slider
%        get(hObject,'Min') and get(hObject,'Max') to determine range of slider


% --- Executes during object creation, after setting all properties.
function amp_slider_CreateFcn(hObject, eventdata, handles)
% hObject    handle to amp_slider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: slider controls usually have a light gray background.
if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor',[.9 .9 .9]);
end
