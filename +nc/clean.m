function clean
  delete('*~');
  delete('#*');
  if (exist('+nc'))
    delete('+nc\*~');
    delete('+nc\#*');
  end    
end
