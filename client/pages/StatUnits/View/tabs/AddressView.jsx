import React from 'react'
import { func, shape, string } from 'prop-types'
import R from 'ramda'

const Address = ({ localize, addressKey, address }) => {
  const list = [
    ...R.range(1, 6).map(v => address[`addressPart${v}`]),
    address.addressDetails,
  ].filter(v => v)
  return (
    <div>
      <div>
        <strong>{localize(addressKey)}</strong>: {R.join(', ', list)}
      </div>
      <div>
        <strong>{localize('RegionCode')}</strong>: {address.region.code}
      </div>
      <div>
        <strong>{localize('GpsCoordinates')}</strong>: {address.gpsCoordinates}
      </div>
    </div>
  )
}

Address.propTypes = {
  localize: func.isRequired,
  addressKey: string.isRequired,
  address: shape({
    addressDetails: string,
    geographicalCodes: string,
    gpsCoordinates: string,
  }).isRequired,
}

export default Address
