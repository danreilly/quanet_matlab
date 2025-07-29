function v = calc_min_inertia(ii, qq)
  iq=-sum(ii.*qq);
  it=[sum(qq.^2) iq; iq sum(ii.^2)]; % inertia tensor
  [v l] = eig(it);
  [mn mi] = min(diag(l));
  v=v(:,mi); % eigenvector of minimal eigenvalue
end
