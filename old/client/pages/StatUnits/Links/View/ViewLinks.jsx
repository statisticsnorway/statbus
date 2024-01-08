import React, { useState, useEffect } from 'react'
import { func, shape, string } from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'

import LinksTree from '../Components/LinksTree/index.js'
import ViewFilter from './ViewFilter.jsx'

function ViewLinks({ localize, findUnit, clear, filter, locale }) {
  const [viewFilter, setViewFilter] = useState(filter)
  const [searchFilter, setSearchFilter] = useState()

  useEffect(() => {
    if (filter) {
      setSearchFilter({ ...filter, type: filter.type === 'any' ? undefined : filter.type })
    }
  }, [filter])

  useEffect(() => () => {
    clear()
  }, [clear])

  const searchUnit = ({ type, ...filter }) => {
    setViewFilter(filter)
    setSearchFilter({ ...filter, type: type === 'any' ? undefined : type })
  }

  return (
    <div>
      <ViewFilter
        isLoading={false}
        value={viewFilter}
        localize={localize}
        locale={locale}
        onFilter={searchUnit}
      />
      <br />
      {searchFilter !== undefined && (
        <Segment>
          <Header as="h4" dividing>
            {localize('SearchResults')}
          </Header>
          <LinksTree filter={searchFilter} getUnitsTree={findUnit} localize={localize} />
        </Segment>
      )}
    </div>
  )
}

ViewLinks.propTypes = {
  localize: func.isRequired,
  findUnit: func.isRequired,
  clear: func.isRequired,
  filter: shape({}),
  locale: string.isRequired,
}

ViewLinks.defaultProps = {
  filter: undefined,
}

export default ViewLinks
