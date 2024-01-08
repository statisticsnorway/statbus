import React from 'react'
import PropTypes from 'prop-types'
import * as R from 'ramda'
import { Container, Table, Button, Grid, Segment, Header } from 'semantic-ui-react'

import { capitalizeFirstLetter } from '/helpers/string'

const getHeaders = R.pipe(R.head, R.dissoc('uid'), R.keys)
const tableWrapperStyle = { maxHeight: '500px', overflow: 'auto' }

const List = ({ id, sampleFrame, list, localize, error }) => {
  if (error !== undefined) return <h2>{localize(error)}</h2>
  if (list.length === 0) return <h2>{localize('Empty')}</h2>
  const headers = getHeaders(list)

  return (
    <Container>
      <Grid>
        <Grid.Row>
          <Grid.Column>
            <br />
            {sampleFrame && (
              <Segment vertical>
                <Header as="h3">{sampleFrame.name}</Header>
              </Segment>
            )}
            {sampleFrame && sampleFrame.description && (
              <Segment size="small" vertical>
                {sampleFrame.description}
              </Segment>
            )}
          </Grid.Column>
        </Grid.Row>
        <Grid.Row>
          <Grid.Column>
            <div style={tableWrapperStyle}>
              <Table basic="very" compact="very" size="small" unstackable>
                <Table.Header>
                  <Table.Row>
                    {headers.map(key => (
                      <Table.HeaderCell
                        key={key}
                        content={localize(capitalizeFirstLetter(key))}
                        textAlign="left"
                      />
                    ))}
                  </Table.Row>
                </Table.Header>
                <Table.Body>
                  {list.map(({ uid, ...unit }) => (
                    <Table.Row key={uid}>
                      {headers.map(key => (
                        <Table.Cell key={key} content={unit[key]} textAlign="left" />
                      ))}
                    </Table.Row>
                  ))}
                </Table.Body>
              </Table>
            </div>
          </Grid.Column>
        </Grid.Row>
        <Grid.Row>
          <Grid.Column>
            <Button
              as="a"
              href={`/api/sampleframes/${id}/download`}
              target="__blank"
              content={localize('DownloadSampleFrame')}
              disabled={![4, 6].includes(Number(sampleFrame.status))}
              icon="download"
              color="blue"
              size="mini"
            />
          </Grid.Column>
        </Grid.Row>
      </Grid>
    </Container>
  )
}

List.propTypes = {
  id: PropTypes.string.isRequired,
  sampleFrame: PropTypes.shape({
    id: PropTypes.number,
    name: PropTypes.string,
    description: PropTypes.string,
  }).isRequired,
  list: PropTypes.arrayOf(PropTypes.shape({
    uid: PropTypes.number.isRequired,
  })).isRequired,
  localize: PropTypes.func.isRequired,
  error: PropTypes.string.isRequired,
}

export default List
