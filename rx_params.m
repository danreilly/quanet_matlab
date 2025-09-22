function rx_params
  tvars = nc.vars_class('tvars.txt');
  tvars.ask('body phase offset' , 'body_ph_offset_deg',0);
  tvars.ask('message fname', 'msg_fname','');
  tvars.ask('frames to skip from first', 'opt_skip_frames', 1);
  tvars.save();
end
