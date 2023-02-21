pragma solidity 0.8.17;

abstract contract GebSafeManagerLike {
    function safes(uint256) virtual public view returns (address);
    function ownsSAFE(uint256) virtual public view returns (address);
    function safeCan(address,uint256,address) virtual public view returns (uint256);
}
