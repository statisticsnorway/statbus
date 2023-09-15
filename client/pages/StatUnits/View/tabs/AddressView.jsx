import React from 'react'
import { func, shape, string } from 'prop-types'
import * as R from 'ramda'

const Address = ({ localize, addressKey, address }) => {
  const list = [
    ...R.range(1, 6).map(v => address[`addressPart${v}`]),
    address.addressDetails,
  ].filter(R.identity)
  return (
    <div>
      <div>
        <strong>{localize(addressKey)}</strong>: {R.join(', ', list)}
      </div>
      <div>
        <strong>{localize('RegionCode')}</strong>: {address.region.code}
      </div>
      <div>
        <strong>{localize('Latitude')}</strong>: {address.latitude}
      </div>
      <div>
        <strong>{localize('Longitude')}</strong>: {address.longitude}
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
    latitude: string,
    longitude: string,
  }).isRequired,
}

export default Address
