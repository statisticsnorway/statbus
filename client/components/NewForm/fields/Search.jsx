import React from 'react'
import { func, string, oneOfType, number } from 'prop-types'

import SearchData from 'components/Search/SearchData'
import SearchField from 'components/Search/SearchField'
import { internalRequest } from 'helpers/request'

const stubF = _ => _
const getSearchData = (name) => {
  switch (name) {
    case 'instSectorCodeId':
      return SearchData.sectorCode
    case 'legalFormId':
      return SearchData.legalForm
    case 'parentOrgLink':
      return SearchData.parentOrgLink
    default:
      throw new Error(`SearchLookup couldn't find SearchData for given name "${name}"`)
  }
}

class Search extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    value: oneOfType([number, string]),
    name: string.isRequired,
    onChange: func.isRequired,
  }

  static defaultProps = {
    value: '',
    data: {},
    errors: [],
  }

  state = {
    data: {},
  }

  componentDidMount() {
    const { name, value } = this.props
    const { editUrl } = getSearchData(name)
    if (value) {
      internalRequest({
        url: `${editUrl}${value}`,
        method: 'get',
        onSuccess: (data) => {
          this.setState({ data })
        },
      })
    }
  }

  setLookupValue = (data) => {
    const { name, onChange } = this.props
    this.setState({ data }, () => onChange({ name, value: data.id }))
  }

  render() {
    const { localize, name } = this.props
    const { data } = this.state
    const searchData = { ...getSearchData(name), data }
    return (
      <SearchField
        localize={localize}
        searchData={searchData}
        onValueSelected={this.setLookupValue}
        onValueChanged={stubF}
      />
    )
  }
}

export default Search
